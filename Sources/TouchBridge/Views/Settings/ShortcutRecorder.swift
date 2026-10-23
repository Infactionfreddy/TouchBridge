import AppKit
import Carbon.HIToolbox
import SwiftUI
import TouchCore

/// Human-readable key combinations, e.g. "⌘[" or "⌃↑", using the current keyboard layout for letters.
enum KeyNames {
    static func display(_ key: KeyCommand) -> String {
        var text = ""
        if key.control { text += "⌃" }
        if key.option { text += "⌥" }
        if key.shift { text += "⇧" }
        if key.command { text += "⌘" }
        return text + name(forKeyCode: key.keyCode)
    }

    static func name(forKeyCode code: UInt16) -> String {
        if let special = specialNames[code] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "key \(code)"
        }
        let layoutData = unsafeBitCast(layoutPointer, to: CFData.self) as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
            UCKeyTranslate(bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                           code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "key \(code)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

enum RecorderOutcome {
    case use(KeyCommand)
    case clear
    case cancel
}

enum RecorderResult {
    case recorded(KeyCommand)
    case cleared
    case cancelled
}

/// Captures the next key combination. Escape cancels, Delete clears.
final class RecorderNSView: NSView {
    var current: KeyCommand? { didSet { needsDisplay = true } }
    var onResult: ((RecorderResult) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = !flags.isDisjoint(with: [.command, .option, .control, .shift])
        switch event.keyCode {
        case 53:
            onResult?(.cancelled)
        case 51, 117 where !hasModifier:
            current = nil
            onResult?(.cleared)
        default:
            let key = KeyCommand(keyCode: event.keyCode,
                                 control: flags.contains(.control), option: flags.contains(.option),
                                 shift: flags.contains(.shift), command: flags.contains(.command))
            current = key
            onResult?(.recorded(key))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        let text = current.map(KeyNames.display) ?? "Press keys…"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: current == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let current: KeyCommand?
    let onResult: (RecorderResult) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.current = current
        view.onResult = onResult
        return view
    }

    func updateNSView(_ view: RecorderNSView, context: Context) {
        view.onResult = onResult
    }
}

/// Sheet: record a shortcut, warn when it has no modifier, confirm with "Use" (or "Clear" after Delete).
struct ShortcutRecorderSheet: View {
    let current: KeyCommand?
    let onDone: (RecorderOutcome) -> Void
    @State private var recorded: KeyCommand?
    @State private var cleared = false
    @State private var warning: String?

    private static func warning(for key: KeyCommand) -> String? {
        (key.control || key.option || key.shift || key.command) ? nil
            : "A shortcut without a modifier key types that key into the frontmost app."
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Press the keyboard shortcut").font(.headline)
            ShortcutRecorder(current: current) { result in
                switch result {
                case .recorded(let key):
                    recorded = key
                    cleared = false
                    warning = Self.warning(for: key)
                case .cleared:
                    recorded = nil
                    cleared = true
                    warning = nil
                case .cancelled:
                    onDone(.cancel)
                }
            }
            .frame(width: 260, height: 44)
            Text(warning ?? "Escape cancels, Delete removes the shortcut.").font(.footnote).foregroundStyle(warning == nil ? Color.secondary : Color.orange)
            HStack {
                Button("Cancel") { onDone(.cancel) }
                if cleared && recorded == nil {
                    Button("Clear") { onDone(.clear) }
                } else {
                    Button("Use") { if let recorded { onDone(.use(recorded)) } }
                        .disabled(recorded == nil)
                }
            }
        }
        .padding(20)
        .onAppear {
            recorded = current
            warning = current.flatMap(Self.warning(for:))
        }
    }
}
