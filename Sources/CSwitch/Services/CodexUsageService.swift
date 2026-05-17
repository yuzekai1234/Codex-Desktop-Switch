import Foundation

enum CodexUsageError: LocalizedError {
    case sessionExpired
    case invalidResponse
    case decodeFailed(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Session expired — add the account again via browser login"
        case .invalidResponse:
            return "Could not read usage data from server"
        case .decodeFailed(let detail):
            return "Could not parse usage data (\(detail))"
        case .httpStatus(let code):
            return "Usage request failed (HTTP \(code))"
        }
    }
}

struct CodexUsageService: Sendable {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let refresher = TokenRefresher()

    func fetchUsage(tokens: AccountTokens) async throws -> (CodexUsageSnapshot, AccountTokens) {
        var current = tokens
        if JWTParser.isExpired(current.accessToken) || JWTParser.isExpired(current.idToken) {
            current = try await refresher.refresh(tokens: current)
        }

        let snapshot = try await requestUsage(tokens: current)
        return (snapshot, current)
    }

    private func requestUsage(tokens: AccountTokens) async throws -> CodexUsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let accountId = tokens.accountId
            ?? JWTParser.accountId(from: tokens.idToken)
            ?? JWTParser.accountId(fromAccessToken: tokens.accessToken)
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexUsageError.invalidResponse
        }

        switch http.statusCode {
        case 200 ..< 300:
            break
        case 401, 403:
            throw CodexUsageError.sessionExpired
        default:
            throw CodexUsageError.httpStatus(http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)
            return try decoded.toSnapshot()
        } catch let decoding as DecodingError {
            throw CodexUsageError.decodeFailed(Self.describe(decoding))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "Missing field: \(key.stringValue)"
        case .typeMismatch(_, let context):
            return "Unexpected field type at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context):
            return "Missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "Invalid usage response"
        }
    }
}
