import Foundation

@main
enum AuditEDIDMain {
    static func main() {
        for (profile, data) in EDIDGenerator.builtInPresets() {
            audit(profile.name, data)
        }
    }

    static func decodeChroma(_ bytes: [UInt8]) -> (rx: Double, ry: Double, gx: Double, gy: Double, bx: Double, by: Double, wx: Double, wy: Double) {
        let rg = Int(bytes[25])
        let bw = Int(bytes[26])
        let rx = Double((Int(bytes[27]) << 2) | ((rg >> 6) & 0x03)) / 1024.0
        let ry = Double((Int(bytes[28]) << 2) | ((rg >> 4) & 0x03)) / 1024.0
        let gx = Double((Int(bytes[29]) << 2) | ((rg >> 2) & 0x03)) / 1024.0
        let gy = Double((Int(bytes[30]) << 2) | (rg & 0x03)) / 1024.0
        let bx = Double((Int(bytes[31]) << 2) | ((bw >> 6) & 0x03)) / 1024.0
        let by = Double((Int(bytes[32]) << 2) | ((bw >> 4) & 0x03)) / 1024.0
        let wx = Double((Int(bytes[33]) << 2) | ((bw >> 2) & 0x03)) / 1024.0
        let wy = Double((Int(bytes[34]) << 2) | (bw & 0x03)) / 1024.0
        return (rx, ry, gx, gy, bx, by, wx, wy)
    }

    static func featureFlags(_ b24: UInt8) -> String {
        var parts: [String] = []
        switch b24 & 0x18 {
        case 0x00: parts.append("RGB-only")
        case 0x08: parts.append("RGB+Y444")
        case 0x10: parts.append("RGB+Y422")
        default: parts.append("RGB+Y444+Y422")
        }
        if b24 & 0x04 != 0 { parts.append("sRGB-default") }
        if b24 & 0x02 != 0 { parts.append("preferred-timing") }
        return parts.joined(separator: ", ")
    }

    static func digitalInput(_ b20: UInt8) -> String {
        let depth = (b20 >> 4) & 0x07
        let iface = b20 & 0x0F
        let depths = ["undef", "6b", "8b", "10b", "12b", "14b", "16b", "undef7"]
        let ifaces = ["undef", "DVI", "HDMIa", "HDMIb", "MDDI", "DisplayPort"]
        let d = depths[Int(depth)]
        let i = Int(iface) < ifaces.count ? ifaces[Int(iface)] : "0x\(String(iface, radix: 16))"
        return "digital \(d) \(i)"
    }

    static func dumpDTD(_ dtd: ArraySlice<UInt8>) -> String {
        let d = Array(dtd)
        let clock = Double(Int(d[0]) | (Int(d[1]) << 8)) / 100.0
        let hActive = Int(d[2]) | ((Int(d[4]) & 0xF0) << 4)
        let hBlank = Int(d[3]) | ((Int(d[4]) & 0x0F) << 8)
        let vActive = Int(d[5]) | ((Int(d[7]) & 0xF0) << 4)
        let vBlank = Int(d[6]) | ((Int(d[7]) & 0x0F) << 8)
        let refresh = clock * 1_000_000 / Double((hActive + hBlank) * (vActive + vBlank))
        return String(format: "%dx%d @ %.3f Hz (%.2f MHz) blank=%d/%d", hActive, vActive, refresh, clock, hBlank, vBlank)
    }

    static func audit(_ name: String, _ data: Data) {
        let b = [UInt8](data)
        var fails = 0
        print("=== \(name) (\(b.count) bytes) ===")
        let sum = b[0..<128].reduce(0) { ($0 + Int($1)) & 0xFF }
        print("  checksum: \(sum == 0 ? "OK" : "BAD")  version \(b[18]).\(b[19])  \(digitalInput(b[20]))")
        print("  features: \(featureFlags(b[24]))")
        let c = decodeChroma(b)
        print(String(format: "  chroma R=(%.3f,%.3f) G=(%.3f,%.3f) B=(%.3f,%.3f) W=(%.3f,%.3f)", c.rx, c.ry, c.gx, c.gy, c.bx, c.by, c.wx, c.wy))
        let targets: [(String, Double, Double, Double, Double)] = [
            ("R", c.rx, c.ry, 0.640, 0.330),
            ("G", c.gx, c.gy, 0.300, 0.600),
            ("B", c.bx, c.by, 0.150, 0.060),
            ("W", c.wx, c.wy, 0.3127, 0.3290),
        ]
        for (label, x, y, tx, ty) in targets {
            if abs(x - tx) > 0.015 || abs(y - ty) > 0.015 {
                print("  FAIL chroma \(label)")
                fails += 1
            }
        }
        if (b[24] & 0x04) == 0 { print("  FAIL: sRGB bit clear"); fails += 1 }
        if (b[24] & 0x02) == 0 { print("  FAIL: preferred bit clear"); fails += 1 }
        if (b[24] & 0x18) != 0 { print("  FAIL: YCbCr claimed in features"); fails += 1 }
        print("  DTD1: \(dumpDTD(b[54..<72]))")
        if b.count >= 256, b[126] > 0 {
            let extSum = b[128..<256].reduce(0) { ($0 + Int($1)) & 0xFF }
            if extSum != 0 { print("  FAIL CTA checksum"); fails += 1 }
            print("  CTA flags=0x\(String(format: "%02X", b[131])) dtd_offset=\(b[130])")
            if b[131] & 0x30 != 0 { print("  FAIL: CTA YCbCr bits set"); fails += 1 }
            if b[130] != 12 { print("  WARN: unexpected dtd_offset \(b[130])") }
            // video block should be at 132
            if b[132] == 0x41 {
                let vic = b[133]
                print("  native VIC=\(vic & 0x7F)")
            }
            if b[134] == 0x65 {
                print(String(format: "  HDMI OUI=%02X%02X%02X", b[137], b[136], b[135]))
            }
        }
        print(fails == 0 ? "  RESULT: PASS\n" : "  RESULT: \(fails) FAILURES\n")
    }
}
