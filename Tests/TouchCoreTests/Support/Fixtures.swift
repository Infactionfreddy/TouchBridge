@testable import TouchCore
import Foundation

enum Fixtures {
    static func elanLayout() throws -> TouchScreenLayout {
        try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(elanDescriptorBytes()))
    }

    static func url(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureError.missing("\(name).\(ext)")
        }
        return url
    }

    static func elanDescriptorBytes() throws -> [UInt8] {
        let text = try String(contentsOf: url("elan-report-descriptor", "hex"), encoding: .utf8)
        return try hexBytes(text)
    }

    static func hexBytes(_ text: String) throws -> [UInt8] {
        let clean = text.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { throw FixtureError.oddHexLength }
        var out: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { throw FixtureError.badHex(String(clean[index..<next])) }
            out.append(byte)
            index = next
        }
        return out
    }

    enum FixtureError: Error { case missing(String), oddHexLength, badHex(String) }
}
