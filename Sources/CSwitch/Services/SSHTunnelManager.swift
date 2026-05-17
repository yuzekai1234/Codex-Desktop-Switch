import Foundation

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
    var lastError: String?
}

final class SSHTunnelManager: @unchecked Sendable {
    static let shared = SSHTunnelManager()

    private let ssh = "/usr/bin/ssh"
    private let lock = NSLock()
    private var process: Process?
    private var terminationObserver: NSObjectProtocol?
    private var lastTerminationError: String?

    func snapshot() -> TunnelSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let running = process?.isRunning == true
        let pid = running ? process?.processIdentifier : nil
        return TunnelSnapshot(
            isRunning: running,
            pid: pid,
            lastError: running ? nil : lastTerminationError
        )
    }

    func start(settings: RemoteSettings) throws {
        lock.lock()
        if process?.isRunning == true {
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
            "-o", "ExitOnForwardFailure=yes",
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
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: proc,
            queue: nil
        ) { [weak self] _ in
            let data = stderrHandle.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self?.handleTermination(
                exitCode: proc.terminationStatus,
                stderrMessage: message
            )
        }
        lastTerminationError = nil
        lock.unlock()

        try proc.run()

        if !proc.isRunning {
            let data = stderrHandle.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errorText = message?.isEmpty == false
                ? message!
                : "SSH failed to start (exit \(proc.terminationStatus))"
            lock.lock()
            lastTerminationError = errorText
            if let terminationObserver {
                NotificationCenter.default.removeObserver(terminationObserver)
            }
            self.terminationObserver = nil
            lock.unlock()
            throw SSHCommandRunnerError.failed(exitCode: proc.terminationStatus, stderr: errorText)
        }

        lock.lock()
        process = proc
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let proc = process
        let observer = terminationObserver
        process = nil
        terminationObserver = nil
        lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        guard let proc else { return }

        if proc.isRunning {
            proc.terminate()
            let pid = proc.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if proc.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    func stopIfRunning() {
        if snapshot().isRunning {
            stop()
        }
    }

    private func handleTermination(exitCode: Int32, stderrMessage: String?) {
        lock.lock()
        process = nil
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        self.terminationObserver = nil
        if exitCode != 0 {
            lastTerminationError = stderrMessage?.isEmpty == false
                ? stderrMessage
                : "SSH exited with code \(exitCode)"
        } else {
            lastTerminationError = nil
        }
        lock.unlock()
    }
}
