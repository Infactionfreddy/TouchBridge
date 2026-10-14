import AppKit
import ApplicationServices
import IOKit.hid

/// Checks and requests Input Monitoring (HID access) and Accessibility (event posting).
@MainActor
final class PermissionCoordinator {
    private var timer: Timer?

    func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openPane("Privacy_ListenEvent")
    }

    func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt (a mutable C global, rejected by Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPane("Privacy_Accessibility")
    }

    func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Calls `onChange` every two seconds until `stopPolling()`.
    func startPolling(_ onChange: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in onChange() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
