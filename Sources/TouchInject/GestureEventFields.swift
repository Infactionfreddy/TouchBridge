import CoreGraphics

/// Undocumented CGEvent fields used to synthesize trackpad gestures. This is the only file that may contain them.
///
/// Sources:
/// - WebKit, Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h: kCGEventGestureHIDType = 110,
///   kCGEventGestureZoomValue = 113, kCGEventGestureRotationValue = 114, kCGEventGestureSwipeValue = 115,
///   kCGEventGesturePhase = 132.
/// - IOKit, IOHIDEventTypes.h: kIOHIDEventTypeRotation = 5, kIOHIDEventTypeZoom = 8.
/// - Touch-Up (RWTH Aachen, MIT), TouchUpCore/TUCCursorUtilities.m: builds the event from a mouse-moved event and
///   additionally sets field 55 = 29 (NSEventTypeGesture), field 50 = 248 and field 101 = 4. The meaning of 50 and 101
///   is not documented; they are set because the Touch-Up recipe is known to work.
enum GestureEventFields {
    static let gestureEventType: Int64 = 29

    static let eventTypeField = field(55)
    static let subtypeField = field(50)
    static let subtypeValue: Int64 = 248
    static let field101 = field(101)
    static let field101Value: Int64 = 4
    static let hidTypeField = field(110)
    static let zoomValueField = field(113)
    static let rotationValueField = field(114)
    static let phaseField = field(132)

    static let hidTypeRotation: Int64 = 5
    static let hidTypeZoom: Int64 = 8

    static let phaseBegan: Int64 = 1
    static let phaseChanged: Int64 = 2
    static let phaseEnded: Int64 = 4
    static let phaseCancelled: Int64 = 8

    static func field(_ raw: UInt32) -> CGEventField {
        CGEventField(rawValue: raw) ?? unsafeBitCast(raw, to: CGEventField.self)
    }
}
