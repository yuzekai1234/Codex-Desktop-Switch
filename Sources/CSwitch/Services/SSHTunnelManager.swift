import Foundation

extension Notification.Name {
    static let tunnelStatusDidChange = Notification.Name("CSwitch.tunnelStatusDidChange")
}

enum SSHTunnelError: LocalizedError {
    case alreadyRunning
    case notRunning
    case executableMissing

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "SSH tunnel is already running"
        case .notRunning: return "SSH tunnel is not running"
        case .executableMissing: return "ssh not found at /usr/bin/ssh"
        }
    }
}

struct TunnelSnapshot: Sendable {
    var isRunning: Bool
    var pid: Int32?
    var statusDetail: String?
    var lastError: String?
    var isLikelyActive: Bool
}

func isRemotePortForwardConflict(_ stderr: String, port: Int) -> Bool {
    let lower = stderr.lowercased()
    return lower.contains("remote port forwarding failed")
        && (lower.contains("\(port)") || lower.contains("listen port"))
}

final class SSHTunnelManager: @unchecked Sendable {
    static let shared = SSHTunnelManager()

    private let ssh = "/usr/bin/ssh"
    private let pgrep = "/usr/bin/pgrep"
    private let lock = NSLock()
    private var process: Process?
    private var trackedPID: Int32?
    private var terminationObserver: NSObjectProtocol?
    private var lastTerminationError: String?
    private var remotePortLikelyActive = false
    private var lastRemotePortForLikelyActive: Int?
    private var discoverySettings: RemoteSettings?

    func inMemorySnapshot() -> TunnelSnapshot {
        snapshot(discoverLocal: false, settings: nil)
    }

    func snapshot(discoverLocal: Bool, settings: RemoteSettings? = nil) -> TunnelSnapshot {
        lock.lock()
        let proc = process
        let tracked = trackedPID
        let likelyActive = remotePortLikelyActive
        let likelyPort = lastRemotePortForLikelyActive
        let lastError = lastTerminationError
        let discovery = settings ?? discoverySettings
        lock.unlock()

        if proc?.isRunning == true {
            return runningSnapshot(pid: proc?.processIdentifier, detail: "Tunnel running")
        }

        if let tracked, processIsAlive(tracked) {
            return runningSnapshot(pid: tracked, detail: "Tunnel running")
        }

        if discoverLocal, let discovery {
            if let pid = discoverExternalTunnel(settings: discovery) {
                return runningSnapshot(pid: pid, detail: "Tunnel running")
            }
        }

        if likelyActive {
            let port = likelyPort ?? discovery?.remoteBindPort ?? 0
            let detail = port > 0
                ? "Remote port \(port) in use — tunnel likely active"
                : "Remote port in use — tunnel likely active"
            return TunnelSnapshot(
                isRunning: true,
                pid: nil,
                statusDetail: detail,
                lastError: nil,
                isLikelyActive: true
            )
        }

        return TunnelSnapshot(
            isRunning: false,
            pid: nil,
            statusDetail: "Tunnel stopped",
            lastError: lastError,
            isLikelyActive: false
        )
    }

    func start(settings: RemoteSettings) throws {
        lock.lock()
        if process?.isRunning == true {
            lock.unlock()
            throw SSHTunnelError.alreadyRunning
        }
        if let trackedPID, processIsAlive(trackedPID) {
            lock.unlock()
            throw SSHTunnelError.alreadyRunning
        }
        lock.unlock()

        guard FileManager.default.isExecutableFile(atPath: ssh) else {
            throw SSHTunnelError.executableMissing
        }

        let config = try settings.validated()
        let forward = "\(config.remoteBindPort):127.0.0.1:\(config.localProxyPort)"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ssh)
        proc.arguments = [
            "-N",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=60",
            "-p", String(config.sshPort),
            "-R", forward,
            config.sshTarget,
        ]

        let stderrPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = stderrPipe
        let stderrHandle = stderrPipe.fileHandleForReading

        lock.lock()
        lastTerminationError = nil
        lock.unlock()

        try proc.run()

        if !proc.isRunning {
            let stderrText = readStderr(stderrHandle)
            if isRemotePortForwardConflict(stderrText, port: config.remoteBindPort) {
                lock.lock()
                remotePortLikelyActive = true
                lastRemotePortForLikelyActive = config.remoteBindPort
                discoverySettings = config
                process = nil
                trackedPID = nil
                lock.unlock()
                postTunnelStatusChanged()
                return
            }

            let errorText = stderrText.isEmpty
                ? "SSH failed to start (exit \(proc.terminationStatus))"
                : stderrText
            lock.lock()
            lastTerminationError = errorText
            lock.unlock()
            throw SSHCommandRunnerError.failed(exitCode: proc.terminationStatus, stderr: errorText)
        }

        let pid = proc.processIdentifier
        lock.lock()
        process = proc
        trackedPID = pid
        remotePortLikelyActive = false
        lastRemotePortForLikelyActive = nil
        discoverySettings = config
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: proc,
            queue: nil
        ) { [weak self] _ in
            let stderrText = self?.readStderr(stderrHandle) ?? ""
            self?.handleTermination(
                exitCode: proc.terminationStatus,
                stderrMessage: stderrText.isEmpty ? nil : stderrText,
                remoteBindPort: config.remoteBindPort
            )
        }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let proc = process
        let observer = terminationObserver
        process = nil
        trackedPID = nil
        terminationObserver = nil
        remotePortLikelyActive = false
        lastRemotePortForLikelyActive = nil
        lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        guard let proc else {
            postTunnelStatusChanged()
            return
        }

        if proc.isRunning {
            proc.terminate()
            let pid = proc.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if proc.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }

        postTunnelStatusChanged()
    }

    func stopIfRunning() {
        if inMemorySnapshot().isRunning {
            stop()
        }
    }

    private func handleTermination(exitCode: Int32, stderrMessage: String?, remoteBindPort: Int) {
        lock.lock()
        process = nil
        trackedPID = nil
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        self.terminationObserver = nil

        if exitCode != 0 {
            let stderr = stderrMessage ?? ""
            if isRemotePortForwardConflict(stderr, port: remoteBindPort) {
                remotePortLikelyActive = true
                lastRemotePortForLikelyActive = remoteBindPort
                lastTerminationError = nil
            } else {
                lastTerminationError = stderr.isEmpty
                    ? "SSH exited with code \(exitCode)"
                    : stderr
            }
        } else {
            lastTerminationError = nil
        }
        lock.unlock()
        postTunnelStatusChanged()
    }

    private func runningSnapshot(pid: Int32?, detail: String) -> TunnelSnapshot {
        TunnelSnapshot(
            isRunning: true,
            pid: pid,
            statusDetail: detail,
            lastError: nil,
            isLikelyActive: false
        )
    }

    private func readStderr(_ handle: FileHandle) -> String {
        let data = handle.availableData
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func discoverExternalTunnel(settings: RemoteSettings) -> Int32? {
        guard let config = try? settings.validated(),
              FileManager.default.isExecutableFile(atPath: pgrep)
        else { return nil }

        let pattern = pgrepPattern(for: config)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pgrep)
        proc.arguments = ["-f", pattern]

        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let firstLine = text.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(trimmed), pid > 0 else { return nil }

        if let managed = process?.processIdentifier, managed == pid, process?.isRunning == true {
            return nil
        }
        return pid
    }

    private func pgrepPattern(for config: RemoteSettings) -> String {
        let forward = "\(config.remoteBindPort):127\\.0\\.0\\.1:\(config.localProxyPort)"
        let target = escapePgrepPattern(config.sshTarget)
        return "ssh.*-R\\s+\(forward).*\(target)"
    }

    private func escapePgrepPattern(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case ".", "^", "$", "[", "]", "(", ")", "{", "}", "*", "+", "?", "|", "\\":
                escaped.append("\\")
                escaped.append(character)
            default:
                escaped.append(character)
            }
        }
        return escaped
    }

    private func postTunnelStatusChanged() {
        NotificationCenter.default.post(name: .tunnelStatusDidChange, object: self)
    }
}
