import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Dock ⌘Q / menu Quit — runs on the main thread before terminate proceeds.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SSHTunnelManager.shared.stopIfRunning()
        return .terminateNow
    }
}
