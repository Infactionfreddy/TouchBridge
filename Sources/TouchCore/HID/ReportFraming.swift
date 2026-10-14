import Foundation

/// IOKit delivers the report as sent on the wire. When the descriptor uses report IDs the first byte is the ID.
public enum ReportFraming {
    /// Returns the payload without the report ID byte, or nil when the report is too short for the layout.
    public static func payload(from raw: [UInt8], reportID: UInt8, layout: TouchScreenLayout) -> [UInt8]? {
        if layout.usesReportIDs, raw.count >= layout.payloadByteCount + 1, raw[0] == reportID {
            return Array(raw.dropFirst())
        }
        if raw.count >= layout.payloadByteCount {
            return raw
        }
        return nil
    }
}
