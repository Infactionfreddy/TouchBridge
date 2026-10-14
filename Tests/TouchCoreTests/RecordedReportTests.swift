import Testing
import Foundation
@testable import TouchCore

@Suite struct RecordedReportTests {
    struct Line: Decodable {
        var t: UInt64
        var id: UInt8
        var hex: String
    }

    @Test(.enabled(if: Fixtures.exists("elan-two-finger", "jsonl"), "elan-two-finger.jsonl not recorded yet — run: swift run hidrecord --seconds 12 --out Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl"))
    func recordedElanSessionDecodes() throws {
        let layout = try Fixtures.elanLayout()
        var decoder = ReportDecoder(layout: layout)
        let text = try String(contentsOf: Fixtures.url("elan-two-finger", "jsonl"), encoding: .utf8)
        var frames: [TouchFrame] = []
        var lastTimestamp: UInt64 = 0
        for line in text.split(separator: "\n") where !line.isEmpty {
            let entry = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
            guard entry.id == layout.reportID else { continue }
            let raw = try Fixtures.hexBytes(entry.hex)
            let payload = try #require(ReportFraming.payload(from: raw, reportID: entry.id, layout: layout))
            #expect(entry.t >= lastTimestamp)
            lastTimestamp = entry.t
            if let frame = decoder.decode(payload: payload, timestamp: entry.t) { frames.append(frame) }
        }
        #expect(frames.count > 50)
        #expect(frames.contains { $0.contacts.count >= 2 })
        for frame in frames {
            for c in frame.contacts {
                #expect((0...layout.logicalMaxX).contains(c.x))
                #expect((0...layout.logicalMaxY).contains(c.y))
                #expect(c.id < 64)
            }
        }
    }
}
