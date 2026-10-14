import Foundation
import CoreGraphics

public struct ActiveTouch: Equatable, Sendable {
    public var id: Int
    public var position: CGPoint
    public var startPosition: CGPoint
    public var startTime: UInt64
    public var lastUpdate: UInt64

    public init(id: Int, position: CGPoint, startPosition: CGPoint, startTime: UInt64, lastUpdate: UInt64) {
        self.id = id
        self.position = position
        self.startPosition = startPosition
        self.startTime = startTime
        self.lastUpdate = lastUpdate
    }
}

public enum TouchPhase: Sendable, Equatable {
    case began, moved, ended
}

public struct TouchEvent: Equatable, Sendable {
    public var id: Int
    public var phase: TouchPhase
    public var position: CGPoint
    public var timestamp: UInt64

    public init(id: Int, phase: TouchPhase, position: CGPoint, timestamp: UInt64) {
        self.id = id
        self.phase = phase
        self.position = position
        self.timestamp = timestamp
    }
}

/// Maintains the set of active contacts across frames and ends contacts that stop being reported.
public struct TouchTracker: Sendable {
    public var stuckTimeout: UInt64
    public private(set) var touches: [ActiveTouch] = []

    public init(stuckTimeout: UInt64 = 500_000_000) {
        self.stuckTimeout = stuckTimeout
    }

    public mutating func process(_ frame: ScreenFrame) -> [TouchEvent] {
        var events: [TouchEvent] = []
        var seen = Set<Int>()
        for contact in frame.contacts {
            if let index = touches.firstIndex(where: { $0.id == contact.id }) {
                if contact.down {
                    touches[index].position = contact.position
                    // A late frame with an older timestamp must not make the contact look stale.
                    touches[index].lastUpdate = max(touches[index].lastUpdate, frame.timestamp)
                    events.append(TouchEvent(id: contact.id, phase: .moved, position: contact.position, timestamp: frame.timestamp))
                    seen.insert(contact.id)
                } else {
                    events.append(TouchEvent(id: contact.id, phase: .ended, position: contact.position, timestamp: frame.timestamp))
                    touches.remove(at: index)
                }
            } else if contact.down {
                touches.append(ActiveTouch(id: contact.id, position: contact.position, startPosition: contact.position,
                                           startTime: frame.timestamp, lastUpdate: frame.timestamp))
                events.append(TouchEvent(id: contact.id, phase: .began, position: contact.position, timestamp: frame.timestamp))
                seen.insert(contact.id)
            }
        }
        for touch in touches where !seen.contains(touch.id) {
            events.append(TouchEvent(id: touch.id, phase: .ended, position: touch.position, timestamp: frame.timestamp))
        }
        touches.removeAll { !seen.contains($0.id) }
        return events
    }

    public mutating func tick(_ timestamp: UInt64) -> [TouchEvent] {
        let expired = touches.filter { timestamp > $0.lastUpdate && timestamp - $0.lastUpdate > stuckTimeout }
        guard !expired.isEmpty else { return [] }
        let ids = Set(expired.map(\.id))
        touches.removeAll { ids.contains($0.id) }
        return expired.map { TouchEvent(id: $0.id, phase: .ended, position: $0.position, timestamp: timestamp) }
    }
}
