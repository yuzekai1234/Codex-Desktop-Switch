import AppKit
import Foundation

enum CodexRelauncherError: LocalizedError {
    case appNotFound

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "Codex Desktop was not found in /Applications."
        }
    }
}

struct CodexRelauncher {
    /// Bundle IDs seen for Codex / ChatGPT desktop builds.
    private static let bundleIdentifiers = [
        "com.openai.codex",
        "com.openai.chatgpt.app",
        "com.openai.chatgpt",
    ]

    private static let applicationNames = ["Codex", "ChatGPT"]

    func restartCodex() throws {
        let workspace = NSWorkspace.shared
        let targets = runningCodexApplications(in: workspace)

        for app in targets {
            app.terminate()
        }

        if !targets.isEmpty {
            waitUntilCodexExits(workspace: workspace, timeout: 12)
        }

        let stubborn = runningCodexApplications(in: workspace)
        if !stubborn.isEmpty {
            for app in stubborn {
                app.forceTerminate()
            }
            waitUntilCodexExits(workspace: workspace, timeout: 8)
        }

        // Brief pause so singleton locks (e.g. auth/session) are released before relaunch.
        Thread.sleep(forTimeInterval: 0.5)

        guard let appURL = resolveCodexAppURL() else {
            throw CodexRelauncherError.appNotFound
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.promptsUserIfNeeded = true

        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        workspace.openApplication(at: appURL, configuration: config) { _, error in
            launchError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        if let launchError {
            throw launchError
        }
    }

    func isCodexRunning() -> Bool {
        !runningCodexApplications(in: NSWorkspace.shared).isEmpty
    }

    // MARK: - Private

    private func runningCodexApplications(in workspace: NSWorkspace) -> [NSRunningApplication] {
        workspace.runningApplications.filter(isCodexApplication)
    }

    private func isCodexApplication(_ app: NSRunningApplication) -> Bool {
        if let bundleId = app.bundleIdentifier, Self.bundleIdentifiers.contains(bundleId) {
            return true
        }
        if let name = app.localizedName, Self.applicationNames.contains(name) {
            return true
        }
        return false
    }

    private func waitUntilCodexExits(workspace: NSWorkspace, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningCodexApplications(in: workspace).isEmpty {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func resolveCodexAppURL() -> URL? {
        let workspace = NSWorkspace.shared
        for bundleId in Self.bundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                return url
            }
        }

        let candidates = [
            "/Applications/Codex.app",
            "/Applications/ChatGPT.app",
            "/Applications/OpenAI Codex.app",
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
