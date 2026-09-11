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
                try apply(path: args[1], displayName: optionValue("--display", in: args))
            case "--reset":
                try reset(displayName: optionValue("--display", in: args))
            case "--capture":
                guard args.count >= 2 else { throw CLIError.usage }
                try capture(path: args[1], displayName: optionValue("--display", in: args))
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

    private static func optionValue(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func resolveDisplay(named name: String?) throws -> ExternalDisplay? {
        let displays = DisplayService.listExternalDisplays()
        guard let name else { return nil }
        let needle = name.lowercased()
        if let match = displays.first(where: { $0.name.lowercased() == needle })
            ?? displays.first(where: { $0.name.lowercased().contains(needle) }) {
            return match
        }
        throw ForceEDIDError.couldNotMatchDisplay(name)
    }

    private static func list() throws {
        let displays = DisplayService.listExternalDisplays()
        guard !displays.isEmpty else { throw ForceEDIDError.noExternalDisplays }
        for display in displays {
            print(display.name)
            print("  id: \(display.id)")
            print("  location: \(display.location)")
            if let uuid = display.uuid {
                print("  uuid: \(uuid)")
            }
        }
    }

    private static func apply(path: String, displayName: String?) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let display = try resolveDisplay(named: displayName)
        try DisplayService.apply(edid: data, to: display)
        if let display {
            print("Applied \(url.lastPathComponent) to \(display.name).")
        } else {
            print("Applied \(url.lastPathComponent) to all external displays.")
        }
    }

    private static func reset(displayName: String?) throws {
        let display = try resolveDisplay(named: displayName)
        try DisplayService.reset(display: display)
        if let display {
            print("Reset \(display.name) to its original EDID.")
        } else {
            print("Reset all external displays to their original EDID.")
        }
    }

    private static func capture(path: String, displayName: String?) throws {
        let display = try resolveDisplay(named: displayName)
            ?? DisplayService.listExternalDisplays().first
        guard let display else { throw ForceEDIDError.noExternalDisplays }
        let data = try DisplayService.captureEDID(from: display)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
        print("Wrote \(data.count) bytes from \(display.name) to \(url.path)")
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
    Force EDID \(AppInfo.versionLabel) — lock a display EDID on Apple Silicon and Intel
    Made by \(AppInfo.maker) — \(AppInfo.makerURL.absoluteString)


    Usage:
      ForceEDID
      ForceEDID --list
      ForceEDID --apply <file.bin> [--display <name>]
      ForceEDID --reset [--display <name>]
      ForceEDID --capture <file.bin> [--display <name>]

    With no arguments the windowed app opens.
    Without --display, apply and reset target every external display.
    Apple Silicon injects a virtual EDID. Intel writes /Library/Displays overrides (admin password).
    """
}

private enum CLIError: LocalizedError {
    case usage

    var errorDescription: String? {
        "Usage: ForceEDID [--list | --apply <file.bin> [--display <name>] | --reset [--display <name>] | --capture <file.bin> [--display <name>]]"
    }
}
