import Foundation

enum AuthRemoteSyncError: LocalizedError {
    case localAuthMissing

    var errorDescription: String? {
        switch self {
        case .localAuthMissing:
            return "Local ~/.codex/auth.json not found. Switch or import an account first."
        }
    }
}

struct AuthRemoteSyncService {
    private let store = AccountStore.shared
    private let ssh = "/usr/bin/ssh"
    private let scp = "/usr/bin/scp"

    func sync(settings: RemoteSettings) throws {
        let config = try settings.validated()
        let localAuth = store.authFileURL

        guard FileManager.default.fileExists(atPath: localAuth.path) else {
            throw AuthRemoteSyncError.localAuthMissing
        }

        let remoteDir = remoteDirectory(for: config.remoteAuthPath)
        try SSHCommandRunner.run(
            executable: ssh,
            arguments: sshBaseArgs(config) + ["\(config.sshTarget)", "mkdir -p \(remoteDir)"]
        )

        let remoteDestination = "\(config.sshTarget):\(config.remoteAuthPath)"
        try SSHCommandRunner.run(
            executable: scp,
            arguments: scpBaseArgs(config) + [localAuth.path, remoteDestination]
        )
    }

    private func sshBaseArgs(_ settings: RemoteSettings) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-p", String(settings.sshPort),
        ]
    }

    private func scpBaseArgs(_ settings: RemoteSettings) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-P", String(settings.sshPort),
        ]
    }

    private func remoteDirectory(for authPath: String) -> String {
        if authPath.hasSuffix("/") {
            return String(authPath.dropLast())
        }
        let nsPath = authPath as NSString
        let dir = nsPath.deletingLastPathComponent
        return dir.isEmpty ? "." : dir
    }
}
