import AppKit
import SwiftUI
import TouchCore

@MainActor
@Observable
final class IdentifierLog {
    var entries: [String] = []

    func add(_ text: String) {
        let stamp = String(format: "%8.3f", Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
        entries.append("\(stamp)  \(text)")
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }
}

/// Receives the events TouchBridge injects and draws the live contacts of the panel.
final class ProbeNSView: NSView {
    var onEvent: ((String) -> Void)?
    var contacts: [Contact] = [] { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func magnify(with event: NSEvent) {
        onEvent?("magnify \(Self.describe(event.phase)) \(String(format: "%+.3f", event.magnification))")
    }

    override func rotate(with event: NSEvent) {
        onEvent?("rotate \(Self.describe(event.phase)) \(String(format: "%+.1f°", event.rotation))")
    }

    override func scrollWheel(with event: NSEvent) {
        onEvent?("scroll phase=\(Self.describe(event.phase)) momentum=\(Self.describe(event.momentumPhase)) dx=\(Int(event.scrollingDeltaX)) dy=\(Int(event.scrollingDeltaY)) precise=\(event.hasPreciseScrollingDeltas)")
    }

    override func swipe(with event: NSEvent) {
        onEvent?("swipe dx=\(event.deltaX) dy=\(event.deltaY)")
    }

    override func mouseDown(with event: NSEvent) { onEvent?("mouseDown clicks=\(event.clickCount)") }
    override func mouseUp(with event: NSEvent) { onEvent?("mouseUp clicks=\(event.clickCount)") }
    override func rightMouseDown(with event: NSEvent) { onEvent?("rightMouseDown") }
    override func rightMouseUp(with event: NSEvent) { onEvent?("rightMouseUp") }
    override func mouseDragged(with event: NSEvent) {
        onEvent?("drag \(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y))")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let window, let primary = NSScreen.screens.first else { return }
        for contact in contacts {
            // Global CG coordinates (origin top-left of the primary display) → Cocoa screen → window → view.
            let cocoa = NSPoint(x: contact.position.x, y: primary.frame.height - contact.position.y)
            let inWindow = window.convertPoint(fromScreen: cocoa)
            let p = convert(inWindow, from: nil)
            let radius: CGFloat = 22
            let circle = NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
            NSColor.systemBlue.withAlphaComponent(0.35).setFill()
            circle.fill()
            NSColor.systemBlue.setStroke()
            circle.lineWidth = 2
            circle.stroke()
            let label = NSAttributedString(string: "\(contact.id)", attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            label.draw(at: NSPoint(x: p.x - 4, y: p.y - 7))
        }
    }

    static func describe(_ phase: NSEvent.Phase) -> String {
        var parts: [String] = []
        if phase.contains(.mayBegin) { parts.append("mayBegin") }
        if phase.contains(.began) { parts.append("began") }
        if phase.contains(.stationary) { parts.append("stationary") }
        if phase.contains(.changed) { parts.append("changed") }
        if phase.contains(.ended) { parts.append("ended") }
        if phase.contains(.cancelled) { parts.append("cancelled") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}

struct EventProbe: NSViewRepresentable {
    let log: IdentifierLog
    let contacts: [Contact]

    func makeNSView(context: Context) -> ProbeNSView {
        let view = ProbeNSView()
        view.onEvent = { [log] text in log.add(text) }
        return view
    }

    func updateNSView(_ view: ProbeNSView, context: Context) {
        view.contacts = contacts
    }
}

struct GestureIdentifierView: View {
    @Bindable var state: AppState
    @State private var log = IdentifierLog()

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Text("Perform gestures on this area. It must lie on the touch display.")
                    .font(.callout).foregroundStyle(.secondary).padding(8)
                EventProbe(log: log, contacts: state.liveContacts)
            }
            .frame(minWidth: 560, minHeight: 480)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Received events").font(.headline)
                    Spacer()
                    Button("Clear") { log.entries.removeAll() }
                }
                .padding(8)
                List(log.entries.reversed(), id: \.self) { entry in
                    Text(entry).font(.system(.caption, design: .monospaced))
                }
            }
            .frame(minWidth: 380)
        }
        .frame(minWidth: 960, minHeight: 520)
    }
}
