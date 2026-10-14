import Foundation
import IOKit.hid
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

/// Prints `message` and the usage to stderr and exits with status 2.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("hidrecord: \(message)\n\(usage)\n".utf8))
    exit(2)
}

var options = Options()
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--shared": options.shared = true
    case "--seconds":
        guard let value = iterator.next() else { fail("--seconds needs a value") }
        guard let seconds = Double(value), seconds.isFinite, seconds > 0 else {
            fail("--seconds needs a positive number, got '\(value)'")
        }
        options.seconds = seconds
    case "--out":
        guard let path = iterator.next() else { fail("--out needs a file path") }
        options.out = path
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        fail("unknown argument: \(argument)")
    }
}

final class Recorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.touchbridge.hidrecord")
    private var layouts: [DeviceID: TouchScreenLayout] = [:]
    private var decoders: [DeviceID: ReportDecoder] = [:]
    private var lastPrint: UInt64 = 0
    private let output: FileHandle?
    private var reportCount = 0
    private var finished = false

    static func describe(_ mode: DeviceOpenMode) -> String {
        switch mode {
        case .exclusive:
            return "exclusive"
        case .shared(let status):
            let hex = String(UInt32(bitPattern: status), radix: 16)
            let hint = status == kIOReturnNotPermitted ? " — Input Monitoring not granted" : ""
            return "shared (seize failed 0x\(hex))\(hint)"
        }
    }

    /// Fails when `outputPath` cannot be created or opened for writing (for example, its directory does not exist).
    init?(outputPath: String?) {
        if let outputPath {
            FileManager.default.createFile(atPath: outputPath, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: outputPath) else { return nil }
            output = handle
        } else {
            output = nil
        }
    }

    func handle(_ event: DeviceEvent) {
        queue.async { self.process(event) }
    }

    /// Closes the output and returns the number of reports recorded; later events are ignored.
    func finish() -> Int {
        queue.sync {
            finished = true
            try? output?.close()
            return reportCount
        }
    }

    private func process(_ event: DeviceEvent) {
        if finished { return }
        switch event {
        case .attached(let id, let info, let mode):
            print("attached: \(info.manufacturer) \(info.product) serial \(info.serial) vid 0x\(String(info.vendorID, radix: 16)) pid 0x\(String(info.productID, radix: 16)) mode=\(Self.describe(mode))")
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

guard let recorder = Recorder(outputPath: options.out) else {
    FileHandle.standardError.write(Data("hidrecord: cannot write to \(options.out ?? "")\n".utf8))
    exit(2)
}
let manager = DeviceManager(preferExclusive: !options.shared, sink: recorder.handle)
print("waiting for a touch screen (usage page 0x0D / usage 0x04)… Ctrl-C to stop")
manager.start()

func shutdown(reason: String) -> Never {
    manager.stop()
    let count = recorder.finish()
    print("done (\(reason)), \(count) reports")
    exit(0)
}

signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler { shutdown(reason: "Ctrl-C") }
sigintSource.resume()

if let seconds = options.seconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        shutdown(reason: "\(seconds)s")
    }
}
RunLoop.main.run()
