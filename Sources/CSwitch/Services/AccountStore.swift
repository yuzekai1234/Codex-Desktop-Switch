import Foundation
import LocalAuthentication
import Security

enum AccountStoreError: LocalizedError {
    case notFound
    case credentialsMissing(String)
    case manifestDecode
    case invalidAuthFile

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Account not found"
        case .credentialsMissing(let label):
            return "No saved login for \(label). Use Add account (browser login) once for this account—after that you can switch without signing in to Codex first."
        case .manifestDecode:
            return "Could not read accounts manifest"
        case .invalidAuthFile:
            return "Invalid Codex auth.json"
        }
    }
}

final class AccountStore: @unchecked Sendable {
    static let shared = AccountStore()

    private let legacyKeychainService = "com.cswitch.accounts"
    private let fileManager = FileManager.default

    private var appSupportURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("C-Switch", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var tokensDirectoryURL: URL {
        let dir = appSupportURL.appendingPathComponent("tokens", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var manifestURL: URL {
        appSupportURL.appendingPathComponent("accounts.json")
    }

    var codexHome: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    var authFileURL: URL {
        codexHome.appendingPathComponent("auth.json")
    }

    func loadManifest() throws -> AccountsManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return AccountsManifest(activeAccountId: nil, accounts: [])
        }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(AccountsManifest.self, from: data)
        } catch {
            throw AccountStoreError.manifestDecode
        }
    }

    func saveManifest(_ manifest: AccountsManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    func saveTokens(_ tokens: AccountTokens, accountId: UUID) throws {
        let url = tokenFileURL(accountId: accountId)
        let data = try JSONEncoder().encode(tokens)
        try data.write(to: url, options: .atomic)
        try restrictToOwnerOnly(url)
        deleteLegacyKeychainItem(accountId: accountId)
    }

    /// Fills missing token files from Keychain or matching `~/.codex/auth.json` (no UI).
    func repairMissingTokenFiles() {
        guard let manifest = try? loadManifest() else { return }

        if manifest.accounts.isEmpty, readCurrentAuthFile() != nil {
            _ = try? importCurrentAuthFile()
            return
        }

        for account in manifest.accounts {
            guard !hasTokenFile(accountId: account.id) else { continue }
            if (try? migrateLegacyKeychainTokens(accountId: account.id)) != nil {
                continue
            }
            _ = try? restoreCredentialsFromCurrentAuthIfMatching(account)
        }
    }

    /// Ensures saved tokens exist, pulling from Codex auth.json when it matches this account.
    func ensureCredentials(for account: AccountRecord) throws {
        if hasStoredCredentials(accountId: account.id) {
            return
        }
        if try restoreCredentialsFromCurrentAuthIfMatching(account) {
            return
        }
        throw AccountStoreError.credentialsMissing(account.label)
    }

    func canRestoreFromCurrentAuth(_ account: AccountRecord) -> Bool {
        guard let auth = readCurrentAuthFile(), auth.authMode == "chatgpt" else {
            return false
        }
        return authMatchesAccount(auth, account: account)
    }

    func loadTokens(accountId: UUID) throws -> AccountTokens {
        let url = tokenFileURL(accountId: accountId)
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AccountTokens.self, from: data)
        }

        if let migrated = try migrateLegacyKeychainTokens(accountId: accountId) {
            return migrated
        }

        throw AccountStoreError.notFound
    }

    func loadTokens(for account: AccountRecord) throws -> AccountTokens {
        try ensureCredentials(for: account)
        return try loadTokens(accountId: account.id)
    }

    func hasStoredCredentials(accountId: UUID) -> Bool {
        if hasTokenFile(accountId: accountId) {
            return true
        }
        return (try? loadLegacyKeychainTokens(accountId: accountId)) != nil
    }

    func hasUsableCredentials(for account: AccountRecord) -> Bool {
        hasStoredCredentials(accountId: account.id) || canRestoreFromCurrentAuth(account)
    }

    func deleteTokens(accountId: UUID) {
        let url = tokenFileURL(accountId: accountId)
        try? fileManager.removeItem(at: url)
        deleteLegacyKeychainItem(accountId: accountId)
    }

    func upsertAccount(
        label: String,
        tokens: AccountTokens,
        authMode: String = "chatgpt",
        existingId: UUID? = nil
    ) throws -> AccountRecord {
        var manifest = try loadManifest()
        let id = existingId ?? UUID()
        let email = JWTParser.email(from: tokens.idToken)
        let plan = JWTParser.plan(from: tokens.idToken)
        let accountId = tokens.accountId ?? JWTParser.accountId(from: tokens.idToken)

        var tokensToStore = tokens
        tokensToStore.accountId = accountId

        try saveTokens(tokensToStore, accountId: id)

        let now = Date()
        if let index = manifest.accounts.firstIndex(where: { $0.id == id }) {
            manifest.accounts[index].label = label
            manifest.accounts[index].email = email
            manifest.accounts[index].plan = plan
            manifest.accounts[index].authMode = authMode
            manifest.accounts[index].accountId = accountId
            manifest.accounts[index].lastUsedAt = now
        } else {
            manifest.accounts.append(
                AccountRecord(
                    id: id,
                    label: label,
                    email: email,
                    plan: plan,
                    authMode: authMode,
                    accountId: accountId,
                    lastUsedAt: now,
                    createdAt: now
                )
            )
        }

        try saveManifest(manifest)
        return manifest.accounts.first { $0.id == id }!
    }

    func deleteAccount(id: UUID) throws {
        var manifest = try loadManifest()
        manifest.accounts.removeAll { $0.id == id }
        if manifest.activeAccountId == id {
            manifest.activeAccountId = nil
        }
        try saveManifest(manifest)
        deleteTokens(accountId: id)
    }

    func renameAccount(id: UUID, label: String) throws {
        var manifest = try loadManifest()
        guard let index = manifest.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.notFound
        }
        manifest.accounts[index].label = label
        try saveManifest(manifest)
    }

    func updateAccountPlan(id: UUID, plan: String?) throws {
        var manifest = try loadManifest()
        guard let index = manifest.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.notFound
        }
        manifest.accounts[index].plan = plan
        try saveManifest(manifest)
    }

    func setActiveAccount(id: UUID) throws {
        var manifest = try loadManifest()
        manifest.activeAccountId = id
        if let index = manifest.accounts.firstIndex(where: { $0.id == id }) {
            manifest.accounts[index].lastUsedAt = Date()
        }
        try saveManifest(manifest)
    }

    func importCurrentAuthFile(label: String? = nil) throws -> AccountRecord {
        guard fileManager.fileExists(atPath: authFileURL.path) else {
            throw AccountStoreError.invalidAuthFile
        }
        let data = try Data(contentsOf: authFileURL)
        let auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        guard auth.authMode == "chatgpt" else {
            throw AccountStoreError.invalidAuthFile
        }

        let tokens = AccountTokens(
            idToken: auth.tokens.idToken,
            accessToken: auth.tokens.accessToken,
            refreshToken: auth.tokens.refreshToken,
            accountId: auth.tokens.accountId ?? JWTParser.accountId(from: auth.tokens.idToken)
        )

        let defaultLabel = label ?? JWTParser.email(from: tokens.idToken) ?? "Imported Account"
        let manifest = try loadManifest()

        if let existing = manifest.accounts.first(where: { $0.accountId == tokens.accountId && tokens.accountId != nil }) {
            return try upsertAccount(label: label ?? existing.label, tokens: tokens, existingId: existing.id)
        }

        return try upsertAccount(label: defaultLabel, tokens: tokens)
    }

    func readCurrentAuthFile() -> CodexAuthFile? {
        guard let data = try? Data(contentsOf: authFileURL) else { return nil }
        return try? JSONDecoder().decode(CodexAuthFile.self, from: data)
    }

    /// Saves tokens for `account` when `~/.codex/auth.json` is the same OpenAI account.
    @discardableResult
    func restoreCredentialsFromCurrentAuthIfMatching(_ account: AccountRecord) throws -> Bool {
        guard !hasTokenFile(accountId: account.id) else { return true }
        guard let auth = readCurrentAuthFile(), auth.authMode == "chatgpt" else {
            return false
        }
        guard authMatchesAccount(auth, account: account) else {
            return false
        }

        let tokens = tokens(from: auth)
        try saveTokens(tokens, accountId: account.id)
        try refreshAccountMetadata(accountId: account.id, tokens: tokens)
        return true
    }

    private func hasTokenFile(accountId: UUID) -> Bool {
        fileManager.fileExists(atPath: tokenFileURL(accountId: accountId).path)
    }

    private func tokens(from auth: CodexAuthFile) -> AccountTokens {
        AccountTokens(
            idToken: auth.tokens.idToken,
            accessToken: auth.tokens.accessToken,
            refreshToken: auth.tokens.refreshToken,
            accountId: auth.tokens.accountId ?? JWTParser.accountId(from: auth.tokens.idToken)
        )
    }

    private func authMatchesAccount(_ auth: CodexAuthFile, account: AccountRecord) -> Bool {
        let tokens = tokens(from: auth)
        let openAIAccountId = tokens.accountId ?? JWTParser.accountId(from: tokens.idToken)
        guard let openAIAccountId else { return false }
        guard let recordAccountId = account.accountId else { return true }
        return recordAccountId == openAIAccountId
    }

    private func refreshAccountMetadata(accountId: UUID, tokens: AccountTokens) throws {
        var manifest = try loadManifest()
        guard let index = manifest.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        manifest.accounts[index].email = JWTParser.email(from: tokens.idToken)
        manifest.accounts[index].plan = JWTParser.plan(from: tokens.idToken)
        manifest.accounts[index].accountId = tokens.accountId ?? JWTParser.accountId(from: tokens.idToken)
        try saveManifest(manifest)
    }

    private func tokenFileURL(accountId: UUID) -> URL {
        tokensDirectoryURL.appendingPathComponent("\(accountId.uuidString).json")
    }

    private func restrictToOwnerOnly(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Legacy Keychain (read once into token files, no UI)

    private func migrateLegacyKeychainTokens(accountId: UUID) throws -> AccountTokens? {
        guard let tokens = try loadLegacyKeychainTokens(accountId: accountId) else {
            return nil
        }
        try saveTokens(tokens, accountId: accountId)
        return tokens
    }

    private func loadLegacyKeychainTokens(accountId: UUID) throws -> AccountTokens? {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: accountId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = String(data: data, encoding: .utf8),
              let payload = json.data(using: .utf8)
        else {
            if status == errSecItemNotFound || status == errSecInteractionNotAllowed {
                return nil
            }
            return nil
        }

        return try JSONDecoder().decode(AccountTokens.self, from: payload)
    }

    private func deleteLegacyKeychainItem(accountId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: accountId.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
