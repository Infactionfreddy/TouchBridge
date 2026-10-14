import CoreGraphics
@testable import TouchCore

/// Milliseconds → nanoseconds.
func ms(_ n: Int) -> UInt64 { UInt64(n) * 1_000_000 }

func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

func touch(_ id: Int, _ x: Double, _ y: Double, start: UInt64 = 0, now: UInt64 = 0) -> ActiveTouch {
    ActiveTouch(id: id, position: pt(x, y), startPosition: pt(x, y), startTime: start, lastUpdate: now)
}

func frame(_ t: UInt64, _ contacts: [(id: Int, x: Double, y: Double, down: Bool)]) -> ScreenFrame {
    ScreenFrame(timestamp: t, contacts: contacts.map { Contact(id: $0.id, position: pt($0.x, $0.y), down: $0.down) })
}
