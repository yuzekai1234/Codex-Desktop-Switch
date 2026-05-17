import Foundation

struct RemoteSettings: Codable, Equatable {
    var host: String
    var username: String
    var localProxyPort: Int
    var remoteBindPort: Int
    var remoteAuthPath: String
    var sshPort: Int

    static let defaults = RemoteSettings(
        host: "",
        username: "",
        localProxyPort: 7890,
        remoteBindPort: 18080,
        remoteAuthPath: "~/.codex/auth.json",
        sshPort: 22
    )

    var sshTarget: String {
        "\(username)@\(host)"
    }

    func tunnelCommandPreview() -> String {
        "ssh -N -R \(remoteBindPort):127.0.0.1:\(localProxyPort) \(sshTarget)"
    }

    func validated() throws -> RemoteSettings {
        var copy = self
        copy.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.remoteAuthPath = remoteAuthPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !copy.host.isEmpty else {
            throw RemoteSettingsValidationError.emptyHost
        }
        guard !copy.username.isEmpty else {
            throw RemoteSettingsValidationError.emptyUsername
        }
        guard !copy.remoteAuthPath.isEmpty else {
            throw RemoteSettingsValidationError.emptyRemotePath
        }
        guard (1 ... 65535).contains(copy.localProxyPort),
              (1 ... 65535).contains(copy.remoteBindPort),
              (1 ... 65535).contains(copy.sshPort)
        else {
            throw RemoteSettingsValidationError.invalidPort
        }
        return copy
    }
}

enum RemoteSettingsValidationError: LocalizedError {
    case emptyHost
    case emptyUsername
    case emptyRemotePath
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .emptyHost: return "Server host is required"
        case .emptyUsername: return "Username is required"
        case .emptyRemotePath: return "Remote auth path is required"
        case .invalidPort: return "Ports must be between 1 and 65535"
        }
    }
}
