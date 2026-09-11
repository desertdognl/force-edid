import CoreFoundation
import Darwin
import Foundation
import IOKit

enum IOAVBridge {
    /// Runtime check so a universal binary does the right thing under Rosetta too.
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static func mainPort() -> mach_port_t {
        kIOMainPortDefault
    }

    static func createWithService(_ service: io_service_t) -> CFTypeRef? {
    createFn?(kCFAllocatorDefault, service)?.takeRetainedValue()
    }

    static func copyEDID(from service: CFTypeRef) -> Data? {
        var edid: CFData?
        let result = copyFn(service, &edid)
        guard result == kIOReturnSuccess, let edid else { return nil }
        return edid as Data
    }

    static func apply(edid: Data, to service: CFTypeRef) -> IOReturn {
        guard let setFn else { return kIOReturnUnsupported }
        return setFn(service, 1, edid as CFData)
    }

    static func reset(_ service: CFTypeRef) -> IOReturn {
        guard let setFn else { return kIOReturnUnsupported }
        return setFn(service, 0, nil)
    }

    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias CopyFn = @convention(c) (CFTypeRef?, UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn
    private typealias SetFn = @convention(c) (CFTypeRef?, UInt32, CFData?) -> IOReturn

    private static let createFn: CreateFn? = symbol("IOAVServiceCreateWithService")
    private static let copyFnRaw: CopyFn? = symbol("IOAVServiceCopyEDID")
    private static let setFn: SetFn? = symbol("IOAVServiceSetVirtualEDIDMode")

    private static func copyFn(_ service: CFTypeRef?, _ edid: inout CFData?) -> IOReturn {
        guard let copyFnRaw else { return kIOReturnUnsupported }
        var unmanaged: Unmanaged<CFData>?
        let result = copyFnRaw(service, &unmanaged)
        edid = unmanaged?.takeRetainedValue()
        return result
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let iokit, let pointer = dlsym(iokit, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
