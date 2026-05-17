import AppKit
import Foundation

enum OAuthServiceError: LocalizedError {
    case exchangeFailed
    case missingTokens

    var errorDescription: String? {
        switch self {
        case .exchangeFailed:
            return "OAuth token exchange failed"
        case .missingTokens:
            return "OAuth response did not include required tokens"
        }
    }
}

final class OAuthService: @unchecked Sendable {
    private var callbackServer: OAuthCallbackServer?

    func login() async throws -> AccountTokens {
        let pkce = PKCE.generate()
        let state = randomState()
        let authURL = buildAuthorizationURL(pkce: pkce, state: state)

        let server = OAuthCallbackServer()
        callbackServer = server

        async let callbackTask = server.waitForCallback(expectedState: state)
        NSWorkspace.shared.open(authURL)

        let callback = try await callbackTask
        callbackServer = nil

        return try await exchangeCode(callback.code, verifier: pkce.verifier)
    }

    func cancelLogin() {
        callbackServer?.cancel()
        callbackServer = nil
    }

    private func buildAuthorizationURL(pkce: PKCEPair, state: String) -> URL {
        var components = URLComponents(url: OAuthConstants.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: OAuthConstants.clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConstants.redirectURI),
            URLQueryItem(name: "scope", value: OAuthConstants.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
        ]
        return components.url!
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> AccountTokens {
        var request = URLRequest(url: OAuthConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "client_id": OAuthConstants.clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": OAuthConstants.redirectURI,
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw OAuthServiceError.exchangeFailed
        }

        let json = try JSONDecoder().decode(TokenResponseJSON.self, from: data)
        guard let access = json.access_token,
              let refresh = json.refresh_token,
              let idToken = json.id_token
        else {
            throw OAuthServiceError.missingTokens
        }

        let accountId = JWTParser.accountId(from: idToken) ?? JWTParser.accountId(fromAccessToken: access)
        return AccountTokens(
            idToken: idToken,
            accessToken: access,
            refreshToken: refresh,
            accountId: accountId
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
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    private func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
