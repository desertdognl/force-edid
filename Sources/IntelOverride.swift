import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

/// Intel Macs ignore IOAV virtual EDID. They still honour override plists in
/// `/Library/Displays/Contents/Resources/Overrides/` (admin required).
enum IntelOverride {
    private static let overridesRoot = "/Library/Displays/Contents/Resources/Overrides"

    static func apply(edid: Data, to display: ExternalDisplay?) throws {
        let targets = display.map { [$0] } ?? DisplayService.listExternalDisplays()
        guard !targets.isEmpty else { throw ForceEDIDError.noExternalDisplays }

        var copies: [(src: URL, dest: URL)] = []
        defer {
            for copy in copies {
                try? FileManager.default.removeItem(at: copy.src)
            }
        }

        for target in targets {
            let (vendor, product) = try identity(for: target)
            let dest = overrideURL(vendor: vendor, product: product)
            if hasOverride(edid, at: dest) { continue }
            let src = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForceEDID-\(UUID().uuidString).plist")
            try plist(edid: edid, name: target.name).write(to: src, options: .atomic)
            copies.append((src, dest))
        }

        guard !copies.isEmpty else { return }
        try privilegedCopy(copies)
    }

    static func reset(display: ExternalDisplay?) throws {
        let targets = display.map { [$0] } ?? DisplayService.listExternalDisplays()
        let existing = targets.compactMap { target -> String? in
            guard let (vendor, product) = try? identity(for: target) else { return nil }
            let path = overrideURL(vendor: vendor, product: product).path
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
        guard !existing.isEmpty else { return }
        let command = existing.map { "rm -f '\($0)'" }.joined(separator: " && ")
        try runAdministrator(command)
    }

    static func captureEDID(from display: ExternalDisplay) throws -> Data {
        if let data = edidFromServicePort(display.displayID), data.count >= 128 {
            return data
        }
        let (vendor, product) = try identity(for: display)
        if let data = edidByMatching(vendor: vendor, product: product), data.count >= 128 {
            return data
        }
        throw ForceEDIDError.captureFailed
    }

    private static func identity(for display: ExternalDisplay) throws -> (UInt32, UInt32) {
        let vendor = CGDisplayVendorNumber(display.displayID)
        let product = CGDisplayModelNumber(display.displayID)
        guard display.displayID != 0, vendor != 0, vendor != 0xFFFF_FFFF else {
            throw ForceEDIDError.couldNotMatchDisplay(display.name)
        }
        return (vendor, product)
    }

    private static func overrideURL(vendor: UInt32, product: UInt32) -> URL {
        URL(fileURLWithPath: overridesRoot)
            .appendingPathComponent(String(format: "DisplayVendorID-%x", vendor))
            .appendingPathComponent(String(format: "DisplayProductID-%x", product))
    }

    private static func plist(edid: Data, name: String) throws -> Data {
        let dict: [String: Any] = [
            "DisplayProductName": name,
            "IODisplayEDID": edid,
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private static func hasOverride(_ edid: Data, at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let existing = plist["IODisplayEDID"] as? Data
        else { return false }
        return existing == edid
    }

    private static func privilegedCopy(_ copies: [(src: URL, dest: URL)]) throws {
        var commands: [String] = []
        for copy in copies {
            let dir = copy.dest.deletingLastPathComponent().path
            commands.append("mkdir -p '\(dir)'")
            commands.append("cp '\(copy.src.path)' '\(copy.dest.path)'")
            commands.append("chmod 644 '\(copy.dest.path)'")
        }
        try runAdministrator(commands.joined(separator: " && "))
    }

    private static func runAdministrator(_ shell: String) throws {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lower = message.lowercased()
        if lower.contains("user canceled") || lower.contains("-128") {
            throw ForceEDIDError.administratorCancelled
        }
        throw ForceEDIDError.overrideFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func edidFromServicePort(_ displayID: CGDirectDisplayID) -> Data? {
        let service = CGDisplayIOServicePort(displayID)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return edid(from: service)
    }

    private static func edidByMatching(vendor: UInt32, product: UInt32) -> Data? {
        for ioClass in ["IODisplay", "IODisplayConnect", "AppleDisplay"] {
            var iterator: io_iterator_t = 0
            let kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(ioClass), &iterator)
            guard kr == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != IO_OBJECT_NULL {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                guard let info = displayInfo(from: service) else { continue }
                let foundVendor = uint32(info[kDisplayVendorID]) ?? uint32(info["DisplayVendorID"])
                let foundProduct = uint32(info[kDisplayProductID]) ?? uint32(info["DisplayProductID"])
                if foundVendor == vendor, foundProduct == product, let data = edid(from: info) {
                    return data
                }
            }
        }
        return nil
    }

    private static func edid(from service: io_service_t) -> Data? {
        guard let info = displayInfo(from: service) else { return nil }
        return edid(from: info)
    }

    private static func displayInfo(from service: io_service_t) -> [String: Any]? {
        guard let unmanaged = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? [String: Any]
    }

    private static func edid(from info: [String: Any]) -> Data? {
        if let data = info[kIODisplayEDIDKey] as? Data, data.count >= 128 { return data }
        if let data = info["IODisplayEDID"] as? Data, data.count >= 128 { return data }
        return nil
    }

    private static func uint32(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 { return value }
        if let value = value as? Int { return UInt32(truncatingIfNeeded: value) }
        if let value = value as? NSNumber { return value.uint32Value }
        return nil
    }
}

@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePort(_ display: CGDirectDisplayID) -> io_service_t
