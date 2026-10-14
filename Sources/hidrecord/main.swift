import Foundation
import TouchCore
import TouchDevice

let usage = """
usage: hidrecord [--shared] [--seconds N] [--out file.jsonl]
  --shared     open the device non-exclusively (default: exclusive / seize)
  --seconds N  stop after N seconds (default: run until Ctrl-C)
  --out FILE   write every raw report as a JSON line {"t":ns,"id":reportID,"hex":"..."}
"""

struct Options {
    var shared = false
    var seconds: Double?
    var out: String?
}

var options = Options()
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--shared": options.shared = true
    case "--seconds": options.seconds = iterator.next().flatMap(Double.init)
    case "--out": options.out = iterator.next()
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        print("unknown argument: \(argument)\n\(usage)")
        exit(2)
    }
}

final class Recorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.touchbridge.hidrecord")
    private var layouts: [DeviceID: TouchScreenLayout] = [:]
    private var decoders: [DeviceID: ReportDecoder] = [:]
    private var lastPrint: UInt64 = 0
    private let output: FileHandle?
    private(set) var reportCount = 0

    init(outputPath: String?) {
        if let outputPath {
            FileManager.default.createFile(atPath: outputPath, contents: nil)
            output = FileHandle(forWritingAtPath: outputPath)
        } else {
            output = nil
        }
    }

    func handle(_ event: DeviceEvent) {
        queue.async { self.process(event) }
    }

    func finish() {
        queue.sync { try? output?.close() }
    }

    private func process(_ event: DeviceEvent) {
        switch event {
        case .attached(let id, let info, let mode):
            print("attached: \(info.manufacturer) \(info.product) serial \(info.serial) vid 0x\(String(info.vendorID, radix: 16)) pid 0x\(String(info.productID, radix: 16)) mode=\(mode == .exclusive ? "exclusive" : "shared")")
            do {
                let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(info.descriptor))
                layouts[id] = layout
                decoders[id] = ReportDecoder(layout: layout)
                print("layout: report \(layout.reportID), \(layout.slots.count) slots, logical \(layout.logicalMaxX)×\(layout.logicalMaxY), payload \(layout.payloadByteCount) bytes")
            } catch {
                print("descriptor not usable: \(error)")
            }
        case .openFailed(_, let info, let status):
            print("open failed for \(info.product): 0x\(String(UInt32(bitPattern: status), radix: 16))")
        case .detached(let id):
            print("detached \(id)")
            layouts[id] = nil
            decoders[id] = nil
        case .report(let id, let reportID, let raw, let timestamp):
            reportCount += 1
            if let output {
                let hex = raw.map { String(format: "%02x", $0) }.joined()
                output.write(Data("{\"t\":\(timestamp),\"id\":\(reportID),\"hex\":\"\(hex)\"}\n".utf8))
            }
            guard let layout = layouts[id], reportID == layout.reportID,
                  let payload = ReportFraming.payload(from: raw, reportID: reportID, layout: layout),
                  let frame = decoders[id]?.decode(payload: payload, timestamp: timestamp) else { return }
            if timestamp - lastPrint > 100_000_000 {
                lastPrint = timestamp
                let contacts = frame.contacts.map { "\($0.id):(\($0.x),\($0.y))\($0.down ? "↓" : "↑")" }.joined(separator: " ")
                print("contacts=\(frame.contacts.count) \(contacts)")
            }
        }
    }
}

let recorder = Recorder(outputPath: options.out)
let manager = DeviceManager(preferExclusive: !options.shared, sink: recorder.handle)
print("waiting for a touch screen (usage page 0x0D / usage 0x04)… Ctrl-C to stop")
manager.start()

signal(SIGINT) { _ in exit(0) }

if let seconds = options.seconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        manager.stop()
        recorder.finish()
        print("done after \(seconds)s, \(recorder.reportCount) reports")
        exit(0)
    }
}
RunLoop.main.run()
