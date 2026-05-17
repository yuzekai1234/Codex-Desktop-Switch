import AppKit
import SwiftUI

@main
struct CSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("C-Switch", systemImage: "arrow.left.arrow.right.circle") {
            MenuContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
