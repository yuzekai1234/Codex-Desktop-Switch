import AppKit
import SwiftUI

/// Hides the extra title-bar strip MenuBarExtra `.window` style adds above content.
struct MenuBarPanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MenuBarPanelWindowBridge())
    }
}

extension View {
    func menuBarPanelChrome() -> some View {
        modifier(MenuBarPanelChrome())
    }
}

private struct MenuBarPanelWindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor.windowBackgroundColor
    }
}
