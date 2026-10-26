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
        let srgbTargets: [(String, Double, Double)] = [
            ("R", 0.640, 0.330),
            ("G", 0.300, 0.600),
            ("B", 0.150, 0.060),
            ("W", 0.3127, 0.3290),
        ]
        for (profile, data) in EDIDGenerator.builtInPresets() {
            let summary = EDIDParser.summarize(data)
            let valid = EDIDParser.isValid(data)
            var issues: [String] = []
            if !valid || !summary.checksumOK { issues.append("checksum/header") }
            if EDIDParser.claimsYCbCr(data) { issues.append("claims YCbCr") }
            if !EDIDParser.hasSRGBDefault(data) { issues.append("sRGB bit clear") }
            if !summary.colorSpace.contains("sRGB") { issues.append("color summary missing sRGB") }
            if summary.colorSpace.contains("YCbCr") { issues.append("color summary still lists YCbCr") }
            if let chroma = EDIDParser.chromaticity(data) {
                let points = [chroma.rx, chroma.ry, chroma.gx, chroma.gy, chroma.bx, chroma.by, chroma.wx, chroma.wy]
                let pairs = [(points[0], points[1]), (points[2], points[3]), (points[4], points[5]), (points[6], points[7])]
                for (index, target) in srgbTargets.enumerated() {
                    let (x, y) = pairs[index]
                    if abs(x - target.1) > 0.015 || abs(y - target.2) > 0.015 {
                        issues.append("chroma \(target.0)")
                    }
                }
            } else {
                issues.append("chroma undecodable")
            }
            let mark = issues.isEmpty ? "OK" : "FAIL (\(issues.joined(separator: ", ")))"
            print("\(profile.name): \(data.count) bytes · \(summary.preferredMode) · \(summary.colorSpace) · \(mark)")
            if !issues.isEmpty { failed += 1 }
        }
        // Update-check helpers (no network).
        if !UpdateChecker.isVersion("1.5.2", greaterThan: "1.5.1")
            || UpdateChecker.isVersion("1.5.1", greaterThan: "1.5.2")
            || UpdateChecker.normalizeVersion("v1.5.2") != "1.5.2" {
            print("Update version compare: FAIL")
            failed += 1
        } else {
            print("Update version compare: OK")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let mondayNine = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9, minute: 0))!
        let nextMonday = UpdateChecker.nextMondayNineAM(after: mondayNine, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9, minute: 0))!
        if abs(nextMonday.timeIntervalSince(expected)) > 1 {
            print("Weekly schedule helpers: FAIL (\(nextMonday) ≠ \(expected))")
            failed += 1
        } else {
            print("Weekly schedule helpers: OK")
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
