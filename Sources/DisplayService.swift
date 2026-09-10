import AppKit
import CoreGraphics
import Foundation
import IOKit

enum DisplayService {
    /// AppKit names only. Never talks to the display coprocessor.
    static func listExternalDisplays() -> [ExternalDisplay] {
        NSScreen.screens.compactMap { screen in
            let name = screen.localizedName
            guard !isBuiltInName(name) else { return nil }
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value ?? 0
            let uuid = uuidString(for: displayID)
            return ExternalDisplay(
                id: uuid ?? "\(name)#\(displayID)",
                name: name,
                displayID: displayID,
                uuid: uuid,
                location: "External",
                registryPath: uuid ?? name,
                vendor: nil,
                product: nil,
                currentEDID: nil
            )
        }
    }

    static var hasExternalDisplay: Bool {
        !listExternalDisplays().isEmpty
    }

    static func apply(edid: Data, to display: ExternalDisplay?) throws {
        try requireExternalDisplay()
        guard IOAVBridge.isAppleSilicon else { throw ForceEDIDError.notAppleSilicon }
        guard EDIDParser.isValid(edid) else { throw ForceEDIDError.invalidEDID }
        try withTargetedAVServices(display) { av in
            let result = IOAVBridge.apply(edid: edid, to: av)
            guard result == kIOReturnSuccess else { throw ForceEDIDError.applyFailed(result) }
        }
    }

    static func reset(display: ExternalDisplay?) throws {
        try requireExternalDisplay()
        guard IOAVBridge.isAppleSilicon else { throw ForceEDIDError.notAppleSilicon }
        try withTargetedAVServices(display) { av in
            let result = IOAVBridge.reset(av)
            guard result == kIOReturnSuccess else { throw ForceEDIDError.resetFailed(result) }
        }
    }

    static func captureEDID(from display: ExternalDisplay) throws -> Data {
        try requireExternalDisplay()
        var captured: Data?
        try withTargetedAVServices(display) { av in
            if captured == nil, let data = IOAVBridge.copyEDID(from: av), data.count >= 128 {
                captured = data
            }
        }
        guard let captured else { throw ForceEDIDError.captureFailed }
        return captured
    }

    private static func requireExternalDisplay() throws {
        guard hasExternalDisplay else { throw ForceEDIDError.noExternalDisplays }
    }

    private static func isBuiltInName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("built-in")
            || n.contains("ingebouwd")
            || n.contains("color lcd")
            || n.contains("liquid retina")
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard displayID != 0, let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// `display == nil` means every external AV service. One-shot; never on a timer.
    private static func withTargetedAVServices(
        _ display: ExternalDisplay?,
        _ body: (CFTypeRef) throws -> Void
    ) throws {
        if let display {
            try withMatchedAVService(display, body)
        } else {
            try withExternalAVServices(body)
        }
    }

    /// Only reached after requireExternalDisplay(). One-shot; never on a timer.
    private static func withExternalAVServices(_ body: (CFTypeRef) throws -> Void) throws {
        let matches = try enumerateExternalAVServices()
        guard !matches.isEmpty else { throw ForceEDIDError.noExternalDisplays }
        for match in matches {
            try body(match.av)
        }
    }

    private static func withMatchedAVService(
        _ display: ExternalDisplay,
        _ body: (CFTypeRef) throws -> Void
    ) throws {
        let matches = try enumerateExternalAVServices()
        guard !matches.isEmpty else { throw ForceEDIDError.noExternalDisplays }
        guard let match = pickAVService(from: matches, for: display) else {
            throw ForceEDIDError.couldNotMatchDisplay(display.name)
        }
        try body(match.av)
    }

    private struct HardwareIdentity: Equatable {
        var vendor: UInt32
        var product: UInt32
        var serial: UInt32
    }

    private struct AVMatch {
        let av: CFTypeRef
        let identity: HardwareIdentity?
        let productName: String?
    }

    /// Depth-first walk: DisplayAttributes identity is a sibling of DCPAVServiceProxy,
    /// so the nearest preceding identity is paired with each external AV service.
    private static func enumerateExternalAVServices() throws -> [AVMatch] {
        let root = IORegistryGetRootEntry(IOAVBridge.mainPort())
        guard root != IO_OBJECT_NULL else { throw ForceEDIDError.noExternalDisplays }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        let kr = IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )
        guard kr == KERN_SUCCESS else { throw ForceEDIDError.noExternalDisplays }
        defer { IOObjectRelease(iterator) }

        var matches: [AVMatch] = []
        var lastIdentity: HardwareIdentity?
        var lastProductName: String?

        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            if let attributes = dictionaryProperty("DisplayAttributes", from: entry),
               let product = attributes["ProductAttributes"] as? [String: Any] {
                if let identity = hardwareIdentity(from: product) {
                    lastIdentity = identity
                }
                if let name = product["ProductName"] as? String, !name.isEmpty {
                    lastProductName = name
                }
            }

            guard ioClassName(entry) == "DCPAVServiceProxy" else { continue }
            let location = stringProperty("Location", from: entry) ?? "Unknown"
            guard location != "Embedded" else { continue }
            guard let av = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
            matches.append(AVMatch(av: av, identity: lastIdentity, productName: lastProductName))
        }

        return matches
    }

    private static func pickAVService(from matches: [AVMatch], for display: ExternalDisplay) -> AVMatch? {
        if matches.count == 1 { return matches[0] }

        let hw = HardwareIdentity(
            vendor: CGDisplayVendorNumber(display.displayID),
            product: CGDisplayModelNumber(display.displayID),
            serial: CGDisplaySerialNumber(display.displayID)
        )

        let exact = matches.filter { $0.identity == hw }
        if exact.count == 1 { return exact[0] }

        let vendorProduct = matches.filter {
            guard let identity = $0.identity else { return false }
            return identity.vendor == hw.vendor && identity.product == hw.product
        }
        if vendorProduct.count == 1 { return vendorProduct[0] }

        let needle = normalizeName(display.name)
        let byName = matches.filter { match in
            guard let productName = match.productName else { return false }
            let haystack = normalizeName(productName)
            return haystack == needle || haystack.contains(needle) || needle.contains(haystack)
        }
        if byName.count == 1 { return byName[0] }

        return nil
    }

    private static func hardwareIdentity(from productAttributes: [String: Any]) -> HardwareIdentity? {
        guard let vendor = uint32(productAttributes["LegacyManufacturerID"]),
              let product = uint32(productAttributes["ProductID"])
        else { return nil }
        return HardwareIdentity(
            vendor: vendor,
            product: product,
            serial: uint32(productAttributes["SerialNumber"]) ?? 0
        )
    }

    private static func uint32(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 { return value }
        if let value = value as? Int { return UInt32(truncatingIfNeeded: value) }
        if let value = value as? NSNumber { return value.uint32Value }
        return nil
    }

    private static func normalizeName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "display", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func ioClassName(_ entry: io_service_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }

    private static func stringProperty(_ key: String, from service: io_service_t) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return unmanaged.takeRetainedValue() as? String
    }

    private static func dictionaryProperty(_ key: String, from service: io_service_t) -> [String: Any]? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return unmanaged.takeRetainedValue() as? [String: Any]
    }
}
