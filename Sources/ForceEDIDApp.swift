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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    state.checkForUpdatesManual()
                }
            }
        }
    }
}

enum WindowCentering {
    private static var didCenter = false

    static func centerIfNeeded() {
        AppDelegate.shared?.attachWindowDelegate()
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
            AppDelegate.shared?.attachWindowDelegate()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        WindowCentering.centerIfNeeded()
        attachWindowDelegate()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let keep = UserDefaults.standard.object(forKey: "keepInMenuBar") as? Bool ?? true
        return !keep
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusBarController.shared.revealMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let keep = UserDefaults.standard.object(forKey: "keepInMenuBar") as? Bool ?? true
        if keep {
            // Hide instead of destroy so the menu bar can reopen the same window.
            sender.orderOut(nil)
            return false
        }
        return true
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        adopt(window)
    }

    func attachWindowDelegate() {
        DispatchQueue.main.async {
            NSApp.windows.forEach { self.adopt($0) }
        }
    }

    private func adopt(_ window: NSWindow) {
        guard window.styleMask.contains(.titled), window.styleMask.contains(.closable) else { return }
        guard !(window is NSPanel) else { return }
        window.delegate = self
    }
}
