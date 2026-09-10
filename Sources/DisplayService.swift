import AppKit
import Foundation
import IOKit

enum DisplayService {
    /// AppKit names only. Never talks to the display coprocessor.
    static func listExternalDisplays() -> [ExternalDisplay] {
        NSScreen.screens.compactMap { screen in
            let name = screen.localizedName
            guard !isBuiltInName(name) else { return nil }
            return ExternalDisplay(
                id: name,
                location: "External",
                registryPath: name,
                name: name,
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
        try withExternalAVServices { av in
            let result = IOAVBridge.apply(edid: edid, to: av)
            guard result == kIOReturnSuccess else { throw ForceEDIDError.applyFailed(result) }
        }
    }

    static func reset(display: ExternalDisplay?) throws {
        try requireExternalDisplay()
        guard IOAVBridge.isAppleSilicon else { throw ForceEDIDError.notAppleSilicon }
        try withExternalAVServices { av in
            let result = IOAVBridge.reset(av)
            guard result == kIOReturnSuccess else { throw ForceEDIDError.resetFailed(result) }
        }
    }

    static func captureEDID(from display: ExternalDisplay) throws -> Data {
        try requireExternalDisplay()
        var captured: Data?
        try withExternalAVServices { av in
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

    /// Only reached after requireExternalDisplay(). One-shot; never on a timer.
    private static func withExternalAVServices(_ body: (CFTypeRef) throws -> Void) throws {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy")
        let kr = IOServiceGetMatchingServices(IOAVBridge.mainPort(), matching, &iterator)
        guard kr == KERN_SUCCESS else { throw ForceEDIDError.noExternalDisplays }
        defer { IOObjectRelease(iterator) }

        var used = 0
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let location = stringProperty("Location", from: service) ?? "Unknown"
            guard location != "Embedded" else { continue }
            guard let av = IOAVServiceCreateWithService(kCFAllocatorDefault, service) else { continue }
            try body(av)
            used += 1
        }

        if used == 0 {
            throw ForceEDIDError.noExternalDisplays
        }
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
}
