import Foundation

enum JWTParser {
    struct Payload: Decodable {
        var email: String?
        var exp: Int?
        var sub: String?
        var auth: OpenAIAuthClaim?

        enum CodingKeys: String, CodingKey {
            case email
            case exp
            case sub
            case auth = "https://api.openai.com/auth"
        }
    }

    struct OpenAIAuthClaim: Decodable {
        var userId: String?
        var chatgptAccountId: String?
        var chatgptPlanType: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case chatgptAccountId = "chatgpt_account_id"
            case chatgptPlanType = "chatgpt_plan_type"
        }
    }

    static func decodePayload(_ jwt: String) -> Payload? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadPart = String(parts[1])
        guard let data = base64URLDecode(payloadPart) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func email(from idToken: String) -> String? {
        decodePayload(idToken)?.email
    }

    static func plan(from idToken: String) -> String? {
        decodePayload(idToken)?.auth?.chatgptPlanType
    }

    static func accountId(from idToken: String) -> String? {
        if let accountId = decodePayload(idToken)?.auth?.chatgptAccountId {
            return accountId
        }
        return decodePayload(idToken)?.auth?.userId ?? decodePayload(idToken)?.sub
    }

    static func accountId(fromAccessToken accessToken: String) -> String? {
        decodePayload(accessToken)?.auth?.userId ?? decodePayload(accessToken)?.sub
    }

    static func isExpired(_ jwt: String, leeway: TimeInterval = 60) -> Bool {
        guard let exp = decodePayload(jwt)?.exp else { return false }
        return Date().timeIntervalSince1970 >= TimeInterval(exp) - leeway
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }
        return Data(base64Encoded: base64)
    }
}
