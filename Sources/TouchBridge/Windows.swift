import AppKit
import SwiftUI

/// Creates and shows auxiliary windows for a menu-bar app without a main window.
@MainActor
final class Windows {
    static let shared = Windows()
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(_ content: Content, title: String, id: String) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.fittingSize)
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
