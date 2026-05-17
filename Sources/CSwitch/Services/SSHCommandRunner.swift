import Foundation

enum SSHCommandRunnerError: LocalizedError {
    case executableMissing(String)
    case failed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "Command not found: \(path)"
        case .failed(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Command failed (exit \(code))"
            }
            return detail
        }
    }
}

enum SSHCommandRunner {
    @discardableResult
    static func run(executable: String, arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw SSHCommandRunnerError.executableMissing(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw SSHCommandRunnerError.failed(exitCode: process.terminationStatus, stderr: stderr)
        }

        return stderr
    }
}
