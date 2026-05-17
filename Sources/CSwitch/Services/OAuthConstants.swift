import Foundation

enum OAuthConstants {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let scope = "openid profile email offline_access"
    static let callbackPort: UInt16 = 1455
}
