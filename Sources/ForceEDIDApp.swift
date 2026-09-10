import AppKit
import SwiftUI

@main
struct ForceEDIDApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        CLI.handleIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Force EDID") {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 840, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum WindowCentering {
    private static var didCenter = false

    static func centerIfNeeded() {
        guard !didCenter else { return }
        didCenter = true
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first else { return }
            let size = NSSize(width: 840, height: 560)
            window.minSize = NSSize(width: 760, height: 500)
            window.maxSize = NSSize(width: 1100, height: 780)
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let x = visible.midX - size.width / 2
            let y = visible.midY - size.height / 2
            window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let keep = UserDefaults.standard.object(forKey: "keepInMenuBar") as? Bool ?? true
        return !keep
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        WindowCentering.centerIfNeeded()
    }
}
