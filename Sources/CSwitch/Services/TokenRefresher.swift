import Foundation

enum TokenRefresherError: LocalizedError {
    case refreshFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .refreshFailed:
            return "Could not refresh access token"
        case .invalidResponse:
            return "Token refresh returned an invalid response"
        }
    }
}

struct TokenRefreshResult {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var expiresAt: Date
}

struct TokenRefresher: Sendable {
    func refresh(tokens: AccountTokens) async throws -> AccountTokens {
        let result = try await refresh(refreshToken: tokens.refreshToken)
        return AccountTokens(
            idToken: result.idToken ?? tokens.idToken,
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            accountId: tokens.accountId ?? JWTParser.accountId(from: result.idToken ?? tokens.idToken)
        )
    }

    func refresh(refreshToken: String) async throws -> TokenRefreshResult {
        var request = URLRequest(url: OAuthConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthConstants.clientID,
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw TokenRefresherError.refreshFailed
        }

        let json = try JSONDecoder().decode(TokenResponseJSON.self, from: data)
        guard let access = json.access_token,
              let refresh = json.refresh_token,
              let expiresIn = json.expires_in
        else {
            throw TokenRefresherError.invalidResponse
        }

        return TokenRefreshResult(
            accessToken: access,
            refreshToken: refresh,
            idToken: json.id_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    private struct TokenResponseJSON: Decodable {
        var access_token: String?
        var refresh_token: String?
        var expires_in: Int?
        var id_token: String?
    }

    private func formBody(_ fields: [String: String]) -> String {
        fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }.joined(separator: "&")
    }
}
