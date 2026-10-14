import AppKit
import CoreGraphics
import TouchCore

/// Resolves which display the touch panel maps to and reports display configuration changes (debounced).
@MainActor
final class DisplayResolver {
    struct DisplayDescription: Identifiable, Equatable {
        var id: CGDirectDisplayID
        var uuid: String
        var name: String
        var frame: CGRect
        var rotation: Int
        var isBuiltin: Bool
    }

    private var onChange: (() -> Void)?
    private var pending: Task<Void, Never>?
    private var observing = false

    deinit {
        if observing {
            CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    func allDisplays() -> [DisplayDescription] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { id in
            DisplayDescription(id: id,
                               uuid: Self.uuid(of: id),
                               name: Self.name(of: id),
                               frame: CGDisplayBounds(id),
                               rotation: Int(CGDisplayRotation(id).rounded()),
                               isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// `.auto` = first display that is not built in, else the first display at all.
    func resolve(_ selection: DisplaySelection) -> DisplayDescription? {
        let displays = allDisplays()
        if case .display(let uuid) = selection, let match = displays.first(where: { $0.uuid == uuid }) {
            return match
        }
        return displays.first { !$0.isBuiltin } ?? displays.first
    }

    /// Replaces the change handler; the CoreGraphics callback is registered only on the first call.
    func startObserving(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        guard !observing else { return }
        observing = true
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Coalesces the burst of callbacks a reconfiguration produces into one `onChange` 300 ms after the last one.
    fileprivate func scheduleChange() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    private static func uuid(of id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
        return screen?.localizedName ?? "Display \(id)"
    }
}

/// CoreGraphics display reconfiguration callback. A file-scope function is nonisolated, so it is safe on whatever
/// thread CoreGraphics calls it from; it only hops to the main actor.
private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                 _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let resolver = Unmanaged<DisplayResolver>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in resolver.scheduleChange() }
}
