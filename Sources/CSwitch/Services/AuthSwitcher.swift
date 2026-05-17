import Foundation

enum AuthSwitcherError: LocalizedError {
    case codexHomeMissing
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .codexHomeMissing:
            return "~/.codex directory is missing or not writable"
        case .writeFailed(let detail):
            return "Failed to write auth.json: \(detail)"
        }
    }
}

struct AuthSwitcher {
    private let store = AccountStore.shared

    func buildAuthFile(from tokens: AccountTokens, authMode: String = "chatgpt") -> CodexAuthFile {
        let accountId = tokens.accountId ?? JWTParser.accountId(from: tokens.idToken)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return CodexAuthFile(
            authMode: authMode,
            openaiAPIKey: nil,
            tokens: CodexAuthTokens(
                idToken: tokens.idToken,
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                accountId: accountId
            ),
            lastRefresh: formatter.string(from: Date())
        )
    }

    @discardableResult
    func switchToAccount(_ account: AccountRecord) async throws -> CodexAuthFile {
        var tokens = try store.loadTokens(for: account)
        if JWTParser.isExpired(tokens.accessToken) || JWTParser.isExpired(tokens.idToken) {
            tokens = try await TokenRefresher().refresh(tokens: tokens)
            try store.saveTokens(tokens, accountId: account.id)
        }

        let authFile = buildAuthFile(from: tokens, authMode: account.authMode)
        try writeAuthFile(authFile)
        try store.setActiveAccount(id: account.id)
        return authFile
    }

    func writeAuthFile(_ authFile: CodexAuthFile) throws {
        let codexHome = store.codexHome
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: codexHome.path) else {
            throw AuthSwitcherError.codexHomeMissing
        }

        let authURL = store.authFileURL
        let backupURL = codexHome.appendingPathComponent("auth.json.cswitch.bak")
        let tempURL = codexHome.appendingPathComponent("auth.json.tmp")

        if fileManager.fileExists(atPath: authURL.path) {
            _ = try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: authURL, to: backupURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(authFile)

        try data.write(to: tempURL, options: .atomic)
        _ = try fileManager.replaceItemAt(authURL, withItemAt: tempURL)
    }

    func rollbackFromBackup() throws {
        let fileManager = FileManager.default
        let backupURL = store.codexHome.appendingPathComponent("auth.json.cswitch.bak")
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        _ = try fileManager.replaceItemAt(store.authFileURL, withItemAt: backupURL)
    }
}
