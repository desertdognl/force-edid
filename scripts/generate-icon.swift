#!/usr/bin/env swift
import AppKit
import Foundation

/// Renders the in-app mark (accent-blue gradient + display.and.arrow.down) as AppIcon.icns.
///
///   swiftc -framework AppKit -o /tmp/force-edid-icon scripts/generate-icon.swift
///   /tmp/force-edid-icon
@main
enum GenerateIcon {
    static func main() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resources = cwd.appendingPathComponent("Resources")
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("ForceEDID.iconset")

        let sizes: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]

        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        for entry in sizes {
            let bitmap = render(pixels: entry.pixels)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("PNG encode failed for \(entry.name)")
            }
            try png.write(to: iconset.appendingPathComponent(entry.name))
        }

        let master = render(pixels: 1024)
        if let png = master.representation(using: .png, properties: [:]) {
            try png.write(to: resources.appendingPathComponent("AppIcon.png"))
        }

        let icns = resources.appendingPathComponent("AppIcon.icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError("iconutil failed")
        }

        try? FileManager.default.removeItem(at: iconset)
        print("Wrote \(icns.path)")
    }

    static func render(pixels: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not create graphics context")
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true

        let rect = NSRect(origin: .zero, size: bitmap.size)
        let top = NSColor(srgbRed: 0.35, green: 0.62, blue: 0.99, alpha: 1)
        let bottom = NSColor(srgbRed: 0.00, green: 0.38, blue: 0.92, alpha: 1)
        NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: 270)

        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.20),
            NSColor.white.withAlphaComponent(0),
        ])!.draw(in: rect, angle: 90)

        let pointSize = CGFloat(pixels) * 0.44
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "display.and.arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            fatalError("Missing SF Symbol display.and.arrow.down")
        }

        let symbolSize = symbol.size
        let x = (CGFloat(pixels) - symbolSize.width) / 2
        let y = (CGFloat(pixels) - symbolSize.height) / 2 - CGFloat(pixels) * 0.015
        symbol.draw(
            in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
