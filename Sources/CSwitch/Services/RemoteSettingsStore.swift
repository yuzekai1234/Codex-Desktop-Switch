import Foundation

enum RemoteSettingsStoreError: LocalizedError {
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed: return "Could not read remote settings"
        }
    }
}

final class RemoteSettingsStore: @unchecked Sendable {
    static let shared = RemoteSettingsStore()

    private let fileManager = FileManager.default

    private var settingsURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("C-Switch", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("remote-settings.json")
    }

    func load() -> RemoteSettings {
        guard fileManager.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(RemoteSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: RemoteSettings) throws {
        let validated = try settings.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try data.write(to: settingsURL, options: .atomic)
    }
}
