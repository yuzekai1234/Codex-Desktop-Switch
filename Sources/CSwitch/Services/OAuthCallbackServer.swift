import Foundation
import Network

enum OAuthCallbackServerError: LocalizedError {
    case portInUse
    case startFailed
    case timedOut
    case invalidCallback

    var errorDescription: String? {
        switch self {
        case .portInUse:
            return "Port 1455 is already in use. Quit other OAuth listeners and try again."
        case .startFailed:
            return "Could not start OAuth callback server"
        case .timedOut:
            return "Login timed out waiting for browser callback"
        case .invalidCallback:
            return "OAuth callback was missing code or state"
        }
    }
}

struct OAuthCallback {
    let code: String
    let state: String
}

final class OAuthCallbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<OAuthCallback, Error>?
    private var expectedState: String?
    private var hasFinished = false
    private let finishLock = NSLock()

    func waitForCallback(expectedState: String, timeout: TimeInterval = 300) async throws -> OAuthCallback {
        self.expectedState = expectedState
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            do {
                let params = NWParameters.tcp
                listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: OAuthConstants.callbackPort)!)
            } catch {
                continuation.resume(throwing: OAuthCallbackServerError.startFailed)
                return
            }

            listener?.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    if (error as NSError).code == Int(EADDRINUSE) {
                        self?.finish(with: .failure(OAuthCallbackServerError.portInUse))
                    } else {
                        self?.finish(with: .failure(OAuthCallbackServerError.startFailed))
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            listener?.start(queue: .global(qos: .userInitiated))

            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.finish(with: .failure(OAuthCallbackServerError.timedOut))
            }
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let responseBody = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>C-Switch</title></head>
            <body style="font-family:-apple-system,sans-serif;text-align:center;padding:48px;">
            <h2>Login successful</h2><p>You can close this tab and return to C-Switch.</p>
            </body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(responseBody.utf8.count)\r
            Connection: close\r
            \r
            \(responseBody)
            """
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            if let callback = self.parseRequest(request) {
                self.finish(with: .success(callback))
            } else {
                self.finish(with: .failure(OAuthCallbackServerError.invalidCallback))
            }
        }
    }

    private func parseRequest(_ request: String) -> OAuthCallback? {
        guard let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])
        guard let components = URLComponents(string: path),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            return nil
        }

        guard state == expectedState else { return nil }
        return OAuthCallback(code: code, state: state)
    }

    private func finish(with result: Result<OAuthCallback, Error>) {
        finishLock.lock()
        defer { finishLock.unlock() }
        guard !hasFinished, let continuation else { return }
        hasFinished = true
        self.continuation = nil
        listener?.cancel()
        listener = nil
        switch result {
        case .success(let callback):
            continuation.resume(returning: callback)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func cancel() {
        finish(with: .failure(OAuthCallbackServerError.timedOut))
    }
}
