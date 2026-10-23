import AppKit

/// Reports the bundle identifier of the frontmost application; nil when macOS reports none.
@MainActor
final class FrontmostAppObserver {
    private(set) var bundleID: String?
    var onChange: ((String?) -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, self.bundleID != id else { return }
                self.bundleID = id
                self.onChange?(id)
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
