import Foundation

enum CLI {
    static func handleIfNeeded() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first, first.hasPrefix("-") else { return }

        do {
            switch first {
            case "-h", "--help":
                print(helpText)
            case "--list":
                try list()
            case "--apply":
                guard args.count >= 2 else { throw CLIError.usage }
                try apply(path: args[1])
            case "--reset":
                try reset()
            case "--capture":
                guard args.count >= 2 else { throw CLIError.usage }
                try capture(path: args[1])
            case "--self-test":
                try selfTest()
            default:
                throw CLIError.usage
            }
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func list() throws {
        let displays = DisplayService.listExternalDisplays()
        guard !displays.isEmpty else { throw ForceEDIDError.noExternalDisplays }
        for display in displays {
            let summary = display.currentEDID.map(EDIDParser.summarize)
            print("\(display.name)")
            print("  location: \(display.location)")
            print("  path: \(display.registryPath)")
            if let summary {
                print("  edid: \(summary.productName) · \(summary.preferredMode) · \(summary.byteCount) bytes")
            }
        }
    }

    private static func apply(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        try DisplayService.apply(edid: data, to: nil)
        print("Applied \(url.lastPathComponent) to all external displays.")
    }

    private static func reset() throws {
        try DisplayService.reset(display: nil)
        print("Reset all external displays to their original EDID.")
    }

    private static func capture(path: String) throws {
        guard let display = DisplayService.listExternalDisplays().first else {
            throw ForceEDIDError.noExternalDisplays
        }
        let data = try DisplayService.captureEDID(from: display)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
        print("Wrote \(data.count) bytes to \(url.path)")
    }

    private static func selfTest() throws {
        var failed = 0
        for (profile, data) in EDIDGenerator.builtInPresets() {
            let summary = EDIDParser.summarize(data)
            let valid = EDIDParser.isValid(data)
            print("\(profile.name): \(data.count) bytes · \(summary.preferredMode) · checksum \(summary.checksumOK ? "OK" : "BAD")")
            if !valid || !summary.checksumOK { failed += 1 }
        }
        guard failed == 0 else {
            fputs("Self-test failed.\n", stderr)
            exit(1)
        }
        print("Self-test passed.")
    }

    private static let helpText = """
    Force EDID \(AppInfo.versionLabel) — lock a display EDID on Apple Silicon
    Made by \(AppInfo.maker) — \(AppInfo.makerURL.absoluteString)


    Usage:
      ForceEDID
      ForceEDID --list
      ForceEDID --apply <file.bin>
      ForceEDID --reset
      ForceEDID --capture <file.bin>

    With no arguments the windowed app opens.
    """
}

private enum CLIError: LocalizedError {
    case usage

    var errorDescription: String? {
        "Usage: ForceEDID [--list | --apply <file.bin> | --reset | --capture <file.bin>]"
    }
}
