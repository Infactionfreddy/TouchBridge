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

    func startObserving(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, _, context in
            guard let context else { return }
            let resolver = Unmanaged<DisplayResolver>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in resolver.scheduleChange() }
        }, context)
    }

    /// Coalesces the burst of callbacks a reconfiguration produces into one `onChange` 300 ms after the last one.
    private func scheduleChange() {
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
