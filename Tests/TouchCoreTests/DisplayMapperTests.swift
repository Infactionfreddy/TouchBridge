import Testing
import Foundation
import CoreGraphics
@testable import TouchCore

@Suite struct DisplayMapperTests {
    let frame = CGRect(x: 3024, y: 0, width: 1920, height: 1080)   // external display right of the main one

    func mapper(orientation: Int = 0, calibration: Calibration? = nil, frame: CGRect? = nil) -> DisplayMapper {
        var cal = calibration ?? Calibration()
        cal.orientation = orientation
        return DisplayMapper(config: MappingConfig(logicalMaxX: 2976, logicalMaxY: 1680,
                                                   displayFrame: frame ?? self.frame, calibration: cal))
    }

    @Test func identityCorners() {
        let m = mapper()
        #expect(m.map(x: 0, y: 0) == CGPoint(x: 3024, y: 0))
        #expect(m.map(x: 2976, y: 1680) == CGPoint(x: 3024 + 1920, y: 1080))
        #expect(m.map(x: 1488, y: 840) == CGPoint(x: 3024 + 960, y: 540))
    }

    @Test func orientations() {
        #expect(mapper(orientation: 90).map(x: 0, y: 0) == CGPoint(x: 3024 + 1920, y: 0))
        #expect(mapper(orientation: 180).map(x: 0, y: 0) == CGPoint(x: 3024 + 1920, y: 1080))
        #expect(mapper(orientation: 270).map(x: 0, y: 0) == CGPoint(x: 3024, y: 1080))
        #expect(mapper(orientation: 90).map(x: 2976, y: 0) == CGPoint(x: 3024 + 1920, y: 1080))
    }

    @Test func calibrationScaleAndOffset() {
        let cal = Calibration(orientation: 0, scaleX: 0.5, scaleY: 2, offsetX: 0.25, offsetY: -0.5)
        let m = mapper(calibration: cal)
        // nx = 0.5*0.5+0.25 = 0.5 ; ny = 0.5*2-0.5 = 0.5
        #expect(m.map(x: 1488, y: 840) == CGPoint(x: 3024 + 960, y: 540))
    }

    @Test func clampsOutsideRange() {
        let m = mapper(calibration: Calibration(orientation: 0, scaleX: 1, scaleY: 1, offsetX: 0.5, offsetY: 0))
        #expect(m.map(x: 2976, y: 0) == CGPoint(x: 3024 + 1920, y: 0))
        #expect(m.map(x: 4000, y: 5000) == CGPoint(x: 3024 + 1920, y: 1080))
        #expect(mapper().map(x: -5, y: -5) == CGPoint(x: 3024, y: 0))
    }

    @Test func negativeOriginDisplay() {
        let m = mapper(frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080))
        #expect(m.map(x: 0, y: 0) == CGPoint(x: -1920, y: -200))
        #expect(m.map(x: 2976, y: 1680) == CGPoint(x: 0, y: 880))
    }

    @Test func mapsWholeFrame() {
        let m = mapper()
        let out = m.map(TouchFrame(timestamp: 7, contacts: [RawContact(id: 2, x: 0, y: 1680, down: true)]))
        #expect(out == ScreenFrame(timestamp: 7, contacts: [Contact(id: 2, position: CGPoint(x: 3024, y: 1080), down: true)]))
    }

    @Test func orientationIsNormalised() throws {
        func decode(_ json: String) throws -> Calibration {
            try JSONDecoder().decode(Calibration.self, from: Data(json.utf8))
        }
        #expect(try decode(#"{"orientation": 450}"#).orientation == 90)
        #expect(try decode(#"{"orientation": 45}"#).orientation == 0)
        #expect(try decode(#"{"orientation": -90}"#).orientation == 270)
        #expect(try decode(#"{"orientation": 180, "scaleX": 2}"#) == Calibration(orientation: 180, scaleX: 2))
    }
}
