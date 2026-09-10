import Foundation

struct ExternalDisplay: Identifiable, Hashable {
    let id: String
    let name: String
    let displayID: UInt32
    let uuid: String?
    let location: String
    let registryPath: String
    let vendor: String?
    let product: String?
    let currentEDID: Data?
}

struct EDIDProfile: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var note: String
    var isPreset: Bool
    var createdAt: Date
    var filename: String

    var isProtected: Bool { isPreset }
}

struct EDIDSummary: Hashable {
    var manufacturer: String
    var productName: String
    var productID: String
    var serial: String
    var version: String
    var preferredMode: String
    var size: String
    var extensionBlocks: Int
    var byteCount: Int
    var checksumOK: Bool
    var warnings: [String]
}

enum AppStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case warning(String)
    case error(String)

    var text: String {
        switch self {
        case .idle: return "Ready."
        case .working(let message), .success(let message), .warning(let message), .error(let message):
            return message
        }
    }
}

enum ForceEDIDError: LocalizedError {
    case notAppleSilicon
    case noExternalDisplays
    case displayNotFound
    case couldNotMatchDisplay(String)
    case invalidEDID
    case cannotReadFile
    case applyFailed(Int32)
    case resetFailed(Int32)
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .notAppleSilicon:
            return "This app only injects EDID on Apple Silicon Macs. Intel Macs use Display Override plists instead."
        case .noExternalDisplays:
            return "No external display services were found. Connect the ATEN receiver and try Refresh."
        case .displayNotFound:
            return "The selected display is no longer available."
        case .couldNotMatchDisplay(let name):
            return "Could not match “\(name)” to a video service. Apply to all if every screen should use this EDID, or unplug the other display and try again."
        case .invalidEDID:
            return "That file is not a valid EDID. Use a raw 128- or 256-byte binary."
        case .cannotReadFile:
            return "The EDID file could not be read."
        case .applyFailed(let code):
            return "macOS rejected the EDID inject (IOReturn 0x\(String(code, radix: 16)))."
        case .resetFailed(let code):
            return "Reset failed (IOReturn 0x\(String(code, radix: 16)))."
        case .captureFailed:
            return "Could not read the current EDID from that display."
        }
    }
}
