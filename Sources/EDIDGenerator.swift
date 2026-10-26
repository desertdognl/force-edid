import Foundation

enum EDIDGenerator {
    struct Timing {
        var pixelClockMHz: Double
        var hActive: Int
        var hBlank: Int
        var hSyncOffset: Int
        var hSyncWidth: Int
        var vActive: Int
        var vBlank: Int
        var vSyncOffset: Int
        var vSyncWidth: Int
        var hSizeMM: Int
        var vSizeMM: Int
        var positiveHSync: Bool
        var positiveVSync: Bool

        var refreshHz: Int {
            let hTotal = hActive + hBlank
            let vTotal = vActive + vBlank
            guard hTotal > 0, vTotal > 0, pixelClockMHz > 0 else { return 60 }
            return Int((pixelClockMHz * 1_000_000 / Double(hTotal * vTotal)).rounded())
        }
    }

    /// VESA sRGB / Rec.709 primaries with D65 white (10-bit EDID encoding).
    private static let sRGBChromaticity: [UInt8] = [
        0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54,
    ]

    static let defaultPresetID = "preset-1080p50-rgb-srgb"

    static func preset(
        id: String,
        name: String,
        note: String,
        timing: Timing,
        productID: UInt16,
        manufacturer: String = "FCE",
        hdmiVIC: UInt8? = nil,
        edidName: String
    ) -> (EDIDProfile, Data) {
        let data = make(
            manufacturer: manufacturer,
            productID: productID,
            year: 2026,
            name: edidName,
            timing: timing,
            hdmiVIC: hdmiVIC
        )
        let profile = EDIDProfile(
            id: id,
            name: name,
            note: note,
            isPreset: true,
            createdAt: Date(timeIntervalSince1970: 0),
            filename: "\(id).bin"
        )
        return (profile, data)
    }

    static func builtInPresets() -> [(EDIDProfile, Data)] {
        let cea1080p50 = Timing(
            pixelClockMHz: 148.50,
            hActive: 1920, hBlank: 720, hSyncOffset: 528, hSyncWidth: 44,
            vActive: 1080, vBlank: 45, vSyncOffset: 4, vSyncWidth: 5,
            hSizeMM: 598, vSizeMM: 336,
            positiveHSync: true, positiveVSync: true
        )
        return [
            preset(
                id: defaultPresetID,
                name: "1920x1080 @ 50 RGB sRGB",
                note: "Default. CEA 1080p50, RGB 4:4:4, sRGB/Rec.709 primaries. No YCbCr.",
                timing: cea1080p50,
                productID: 0x5050,
                hdmiVIC: 31,
                edidName: "1080p50 sRGB"
            ),
            preset(
                id: "preset-1080p50-rgb-dvi",
                name: "1920x1080 @ 50 RGB DVI",
                note: "Same 1080p50 RGB sRGB without an HDMI/CTA block. Use if the extender mishandles HDMI color.",
                timing: cea1080p50,
                productID: 0x5051,
                edidName: "1080p50 DVI"
            ),
            preset(
                id: "preset-720p60",
                name: "720p60 RGB sRGB",
                note: "Lowest-bandwidth RGB fallback if the ATEN link will not stay up.",
                timing: Timing(
                    pixelClockMHz: 74.25,
                    hActive: 1280, hBlank: 370, hSyncOffset: 110, hSyncWidth: 40,
                    vActive: 720, vBlank: 30, vSyncOffset: 5, vSyncWidth: 5,
                    hSizeMM: 598, vSizeMM: 336,
                    positiveHSync: true, positiveVSync: true
                ),
                productID: 0x0720,
                hdmiVIC: 4,
                edidName: "720p60 sRGB"
            ),
            preset(
                id: "preset-1080p60",
                name: "1080p60 RGB sRGB",
                note: "RGB 4:4:4 sRGB lock for HDMI Cat6 / HDBaseT-class ATEN extenders.",
                timing: Timing(
                    pixelClockMHz: 148.50,
                    hActive: 1920, hBlank: 280, hSyncOffset: 88, hSyncWidth: 44,
                    vActive: 1080, vBlank: 45, vSyncOffset: 4, vSyncWidth: 5,
                    hSizeMM: 598, vSizeMM: 336,
                    positiveHSync: true, positiveVSync: true
                ),
                productID: 0x1060,
                hdmiVIC: 16,
                edidName: "1080p60 sRGB"
            ),
            preset(
                id: "preset-1440p60",
                name: "1440p60 RGB sRGB",
                note: "2560×1440 at 60 Hz RGB. Use only if the extender and cable can carry it.",
                timing: Timing(
                    pixelClockMHz: 241.50,
                    hActive: 2560, hBlank: 160, hSyncOffset: 48, hSyncWidth: 32,
                    vActive: 1440, vBlank: 41, vSyncOffset: 3, vSyncWidth: 5,
                    hSizeMM: 598, vSizeMM: 336,
                    positiveHSync: true, positiveVSync: false
                ),
                productID: 0x1440,
                edidName: "1440p60 sRGB"
            ),
            preset(
                id: "preset-2160p30",
                name: "4K30 RGB sRGB",
                note: "Typical ATEN HDMI Cat6 ceiling (4K30 RGB). Prefer this over 4K60 on those boxes.",
                timing: Timing(
                    pixelClockMHz: 297.00,
                    hActive: 3840, hBlank: 560, hSyncOffset: 176, hSyncWidth: 88,
                    vActive: 2160, vBlank: 90, vSyncOffset: 8, vSyncWidth: 10,
                    hSizeMM: 598, vSizeMM: 336,
                    positiveHSync: true, positiveVSync: true
                ),
                productID: 0x2160,
                hdmiVIC: 95,
                edidName: "4K30 sRGB"
            ),
            preset(
                id: "preset-2160p60",
                name: "4K60 RGB sRGB",
                note: "Needs HDMI 2.0 bandwidth. Will drop on 4K30-only ATEN extenders.",
                timing: Timing(
                    pixelClockMHz: 594.00,
                    hActive: 3840, hBlank: 560, hSyncOffset: 176, hSyncWidth: 88,
                    vActive: 2160, vBlank: 90, vSyncOffset: 8, vSyncWidth: 10,
                    hSizeMM: 598, vSizeMM: 336,
                    positiveHSync: true, positiveVSync: true
                ),
                productID: 0x2161,
                hdmiVIC: 97,
                edidName: "4K60 sRGB"
            )
        ]
    }

    static func make(
        manufacturer: String,
        productID: UInt16,
        year: Int,
        name: String,
        timing: Timing,
        hdmiVIC: UInt8? = nil
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: hdmiVIC == nil ? 128 : 256)
        bytes.replaceSubrange(0..<8, with: EDIDParser.header)
        writeManufacturer(&bytes, manufacturer)
        bytes[10] = UInt8(productID & 0xFF)
        bytes[11] = UInt8((productID >> 8) & 0xFF)
        bytes[16] = 1
        bytes[17] = UInt8(max(0, year - 1990))
        bytes[18] = 1
        bytes[19] = 4
        // Digital, 8-bit. HDMI-a when we include CTA; DVI otherwise.
        bytes[20] = hdmiVIC == nil ? 0xA1 : 0xA2
        bytes[21] = UInt8(max(1, timing.hSizeMM / 10))
        bytes[22] = UInt8(max(1, timing.vSizeMM / 10))
        bytes[23] = 0x78
        // Feature Support: preferred timing + sRGB. Bits 3–4 = 00 → RGB 4:4:4 only
        // (0x0E wrongly set bit 3 and advertised YCbCr 4:4:4).
        bytes[24] = 0x06
        bytes.replaceSubrange(25..<35, with: sRGBChromaticity)
        bytes[35] = 0x21
        bytes[36] = 0x08
        bytes[37] = 0x00
        writeStandardTimings(&bytes, timing: timing)
        bytes.replaceSubrange(54..<72, with: encodeDTD(timing))
        bytes.replaceSubrange(72..<90, with: nameDescriptor(name))
        bytes.replaceSubrange(90..<108, with: rangeDescriptor(timing))
        bytes.replaceSubrange(108..<126, with: unusedDescriptor())
        if let vic = hdmiVIC {
            bytes[126] = 1
            EDIDParser.applyChecksum(&bytes, offset: 0)
            let extensionBlock = ctaExtension(nativeVIC: vic)
            bytes.replaceSubrange(128..<256, with: extensionBlock)
        } else {
            bytes[126] = 0
            EDIDParser.applyChecksum(&bytes, offset: 0)
        }
        return Data(bytes)
    }

    private static func ctaExtension(nativeVIC: UInt8) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x02
        block[1] = 0x03
        block[2] = 0x0C
        // Basic audio, no YCbCr 4:4:4 / 4:2:2 — RGB only.
        block[3] = 0x40
        block[4] = 0x41
        block[5] = nativeVIC | 0x80
        block[6] = 0x65
        block[7] = 0x03
        block[8] = 0x0C
        block[9] = 0x00
        block[10] = 0x10
        block[11] = 0x00
        EDIDParser.applyChecksum(&block)
        return block
    }

    private static func writeManufacturer(_ bytes: inout [UInt8], _ name: String) {
        let letters = Array(name.uppercased().padding(toLength: 3, withPad: "X", startingAt: 0).prefix(3))
        func code(_ character: Character) -> UInt16 {
            UInt16((character.asciiValue ?? 65) - 64) & 0x1F
        }
        let packed = (code(letters[0]) << 10) | (code(letters[1]) << 5) | code(letters[2])
        bytes[8] = UInt8((packed >> 8) & 0xFF)
        bytes[9] = UInt8(packed & 0xFF)
    }

    private static func writeStandardTimings(_ bytes: inout [UInt8], timing: Timing) {
        for i in 0..<8 {
            bytes[38 + i * 2] = 0x01
            bytes[39 + i * 2] = 0x01
        }
        // Standard timings can only encode 60 Hz and above. Skip them for 50 Hz
        // so macOS does not pick 1080p60 over the preferred 1080p50 DTD.
        guard timing.refreshHz >= 59 else { return }
        if timing.hActive >= 1280 {
            writeStandardTiming(&bytes, index: 0, width: 1280, height: 720, refresh: 60)
        }
        if timing.hActive >= 1920 {
            writeStandardTiming(&bytes, index: 1, width: 1920, height: 1080, refresh: 60)
        }
        if timing.hActive >= 2560 {
            writeStandardTiming(&bytes, index: 2, width: 2560, height: 1440, refresh: 60)
        }
    }

    private static func writeStandardTiming(_ bytes: inout [UInt8], index: Int, width: Int, height: Int, refresh: Int) {
        let horizontal = UInt8(((width / 8) - 31) & 0xFF)
        let aspect: UInt8
        switch (width, height) {
        case (_, _) where width * 9 == height * 16: aspect = 0b11
        case (_, _) where width * 10 == height * 16: aspect = 0b01
        case (_, _) where width * 4 == height * 5: aspect = 0b00
        default: aspect = 0b10
        }
        bytes[38 + index * 2] = horizontal
        bytes[39 + index * 2] = (aspect << 6) | UInt8((refresh - 60) & 0x3F)
    }

    private static func encodeDTD(_ timing: Timing) -> [UInt8] {
        var dtd = [UInt8](repeating: 0, count: 18)
        let clock = Int((timing.pixelClockMHz * 100.0).rounded())
        dtd[0] = UInt8(clock & 0xFF)
        dtd[1] = UInt8((clock >> 8) & 0xFF)
        dtd[2] = UInt8(timing.hActive & 0xFF)
        dtd[3] = UInt8(timing.hBlank & 0xFF)
        dtd[4] = UInt8(((timing.hActive >> 8) << 4) | ((timing.hBlank >> 8) & 0x0F))
        dtd[5] = UInt8(timing.vActive & 0xFF)
        dtd[6] = UInt8(timing.vBlank & 0xFF)
        dtd[7] = UInt8(((timing.vActive >> 8) << 4) | ((timing.vBlank >> 8) & 0x0F))
        dtd[8] = UInt8(timing.hSyncOffset & 0xFF)
        dtd[9] = UInt8(timing.hSyncWidth & 0xFF)
        dtd[10] = UInt8(((timing.vSyncOffset & 0x0F) << 4) | (timing.vSyncWidth & 0x0F))
        let hOffHi = (timing.hSyncOffset >> 8) & 0x03
        let hWidthHi = (timing.hSyncWidth >> 8) & 0x03
        let vOffHi = (timing.vSyncOffset >> 4) & 0x03
        let vWidthHi = (timing.vSyncWidth >> 4) & 0x03
        dtd[11] = UInt8((hOffHi << 6) | (hWidthHi << 4) | (vOffHi << 2) | vWidthHi)
        dtd[12] = UInt8(timing.hSizeMM & 0xFF)
        dtd[13] = UInt8(timing.vSizeMM & 0xFF)
        dtd[14] = UInt8(((timing.hSizeMM >> 8) << 4) | ((timing.vSizeMM >> 8) & 0x0F))
        var flags: UInt8 = 0x18
        if timing.positiveHSync { flags |= 0x02 }
        if timing.positiveVSync { flags |= 0x04 }
        dtd[17] = flags
        return dtd
    }

    private static func nameDescriptor(_ name: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0x20, count: 18)
        bytes[3] = 0xFC
        let cleaned = String(name.prefix(13)).padding(toLength: 13, withPad: " ", startingAt: 0)
        let ascii = Array(cleaned.utf8.prefix(13))
        for (index, value) in ascii.enumerated() {
            bytes[5 + index] = value
        }
        if let firstPad = bytes[5..<18].firstIndex(of: 0x20) {
            bytes[firstPad] = 0x0A
        }
        return bytes
    }

    private static func rangeDescriptor(_ timing: Timing) -> [UInt8] {
        var bytes = [UInt8](repeating: 0x20, count: 18)
        bytes[3] = 0xFD
        let refresh = timing.refreshHz
        bytes[5] = UInt8(max(24, refresh - 2))
        bytes[6] = UInt8(min(75, refresh + 2))
        bytes[7] = 15
        bytes[8] = 160
        bytes[9] = UInt8(min(255, Int((timing.pixelClockMHz / 10.0).rounded(.up))))
        bytes[10] = 0x0A
        return bytes
    }

    private static func unusedDescriptor() -> [UInt8] {
        var bytes = [UInt8](repeating: 0x00, count: 18)
        bytes[3] = 0x10
        return bytes
    }
}
