import Foundation

struct AccountRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var label: String
    var email: String?
    var plan: String?
    var authMode: String
    var accountId: String?
    var lastUsedAt: Date?
    var createdAt: Date
}

struct AccountsManifest: Codable {
    var activeAccountId: UUID?
    var accounts: [AccountRecord]
}

struct AccountTokens: Codable, Equatable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var accountId: String?
}

struct CodexAuthFile: Codable {
    var authMode: String
    var openaiAPIKey: String?
    var tokens: CodexAuthTokens
    var lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openaiAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
    }
}

struct CodexAuthTokens: Codable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var accountId: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountId = "account_id"
    }
}
