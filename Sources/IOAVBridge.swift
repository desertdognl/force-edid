import CoreFoundation
import Foundation
import IOKit

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> CFTypeRef?

@_silgen_name("IOAVServiceCopyEDID")
func IOAVServiceCopyEDID(_ service: CFTypeRef?, _ edidData: UnsafeMutablePointer<CFData?>) -> IOReturn

@_silgen_name("IOAVServiceSetVirtualEDIDMode")
func IOAVServiceSetVirtualEDIDMode(_ service: CFTypeRef?, _ mode: UInt32, _ edidData: CFData?) -> IOReturn

enum IOAVBridge {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static func mainPort() -> mach_port_t {
        kIOMainPortDefault
    }

    static func copyEDID(from service: CFTypeRef) -> Data? {
        var edid: CFData?
        let result = IOAVServiceCopyEDID(service, &edid)
        guard result == kIOReturnSuccess, let edid else { return nil }
        return edid as Data
    }

    static func apply(edid: Data, to service: CFTypeRef) -> IOReturn {
        IOAVServiceSetVirtualEDIDMode(service, 1, edid as CFData)
    }

    static func reset(_ service: CFTypeRef) -> IOReturn {
        IOAVServiceSetVirtualEDIDMode(service, 0, nil)
    }
}
