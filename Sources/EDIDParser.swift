import Foundation

enum EDIDParser {
    static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    static func isValid(_ data: Data) -> Bool {
        guard data.count == 128 || data.count == 256 || data.count == 384 else { return false }
        let bytes = [UInt8](data)
        guard bytes.starts(with: header) else { return false }
        return checksumOK(bytes, offset: 0)
    }

    static func summarize(_ data: Data) -> EDIDSummary {
        let bytes = [UInt8](data)
        let validHeader = bytes.count >= 128 && bytes.starts(with: header)
        let name = validHeader ? monitorName(bytes) : "Unknown"
        let manufacturer = validHeader ? manufacturerID(bytes) : "???"
        let product = validHeader ? String(format: "0x%04X", productID(bytes)) : "—"
        let serial = validHeader ? String(serialNumber(bytes)) : "—"
        let version = validHeader ? "\(bytes[18]).\(bytes[19])" : "—"
        let mode = validHeader ? preferredMode(bytes) : "—"
        let size = validHeader ? physicalSize(bytes) : "—"
        let extensions = validHeader ? Int(bytes[126]) : 0
        let checksum = validHeader && checksumOK(bytes, offset: 0)
        var warnings: [String] = []

        if !validHeader {
            warnings.append("Missing the standard EDID header.")
        } else if !checksum {
            warnings.append("Base-block checksum is wrong. macOS may ignore this file.")
        }
        if bytes.count > 128 {
            for block in 1..<(bytes.count / 128) {
                if !checksumOK(bytes, offset: block * 128) {
                    warnings.append("Extension block \(block) checksum is wrong.")
                }
            }
        }
        if extensions == 0 {
            warnings.append("No CTA/HDMI extension. Fine for many extenders; HDMI audio may be limited.")
        }

        return EDIDSummary(
            manufacturer: manufacturer,
            productName: name.isEmpty ? "Unnamed display" : name,
            productID: product,
            serial: serial,
            version: version,
            preferredMode: mode,
            size: size,
            extensionBlocks: extensions,
            byteCount: data.count,
            checksumOK: checksum,
            warnings: warnings
        )
    }

    static func hexDump(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func checksumOK(_ bytes: [UInt8], offset: Int) -> Bool {
        guard bytes.count >= offset + 128 else { return false }
        let sum = bytes[offset..<(offset + 128)].reduce(0) { ($0 + Int($1)) & 0xFF }
        return sum == 0
    }

    static func applyChecksum(_ bytes: inout [UInt8], offset: Int = 0) {
        guard bytes.count >= offset + 128 else { return }
        var sum = 0
        for i in offset..<(offset + 127) {
            sum = (sum + Int(bytes[i])) & 0xFF
        }
        bytes[offset + 127] = UInt8((256 - sum) & 0xFF)
    }

    private static func manufacturerID(_ bytes: [UInt8]) -> String {
        let id = (UInt16(bytes[8]) << 8) | UInt16(bytes[9])
        func letter(_ shift: UInt16) -> Character {
            let value = Int((id >> shift) & 0x1F)
            return Character(UnicodeScalar(64 + max(value, 1))!)
        }
        return String([letter(10), letter(5), letter(0)])
    }

    private static func productID(_ bytes: [UInt8]) -> UInt16 {
        UInt16(bytes[10]) | (UInt16(bytes[11]) << 8)
    }

    private static func serialNumber(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[12])
            | (UInt32(bytes[13]) << 8)
            | (UInt32(bytes[14]) << 16)
            | (UInt32(bytes[15]) << 24)
    }

    private static func monitorName(_ bytes: [UInt8]) -> String {
        for descriptor in descriptors(bytes) where descriptor[3] == 0xFC {
            let raw = descriptor[5..<18]
            let text = raw.split(separator: 0x0A, maxSplits: 1, omittingEmptySubsequences: false).first ?? raw
            return String(bytes: text.filter { $0 >= 32 && $0 < 127 }, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return ""
    }

    private static func physicalSize(_ bytes: [UInt8]) -> String {
        let width = Int(bytes[21])
        let height = Int(bytes[22])
        guard width > 0, height > 0 else { return "Not specified" }
        let diagonal = (Double(width * width + height * height)).squareRoot() / 2.54
        return String(format: "%d × %d cm · ~%.0f\"", width, height, diagonal)
    }

    private static func preferredMode(_ bytes: [UInt8]) -> String {
        let dtd = Array(bytes[54..<72])
        if dtd.allSatisfy({ $0 == 0 }) { return "None" }
        let clock = Double(Int(dtd[0]) | (Int(dtd[1]) << 8)) / 100.0
        let hActive = Int(dtd[2]) | ((Int(dtd[4]) & 0xF0) << 4)
        let hBlank = Int(dtd[3]) | ((Int(dtd[4]) & 0x0F) << 8)
        let vActive = Int(dtd[5]) | ((Int(dtd[7]) & 0xF0) << 4)
        let vBlank = Int(dtd[6]) | ((Int(dtd[7]) & 0x0F) << 8)
        let hTotal = hActive + hBlank
        let vTotal = vActive + vBlank
        guard hTotal > 0, vTotal > 0, clock > 0 else {
            return "\(hActive)×\(vActive)"
        }
        let refresh = (clock * 1_000_000) / Double(hTotal * vTotal)
        return String(format: "%d×%d @ %.0f Hz · %.2f MHz", hActive, vActive, refresh, clock)
    }

    private static func descriptors(_ bytes: [UInt8]) -> [[UInt8]] {
        stride(from: 54, through: 108, by: 18).map { Array(bytes[$0..<($0 + 18)]) }
    }
}
