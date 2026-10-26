import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    private var item: NSStatusItem?
    private weak var state: AppState?
    private var fallbackWindow: NSWindow?

    func sync(from state: AppState, enabled: Bool) {
        self.state = state
        if enabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        if item == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem.button?.image = NSImage(
                systemSymbolName: "display.and.arrow.down",
                accessibilityDescription: "Force EDID"
            )
            item = statusItem
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Force EDID", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Apply assigned EDIDs", action: #selector(apply), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh displays", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "DesertDog", action: #selector(openSite), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items {
            entry.target = self
        }
        item.menu = menu
    }

    private func remove() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        item = nil
    }

    func revealMainWindow() {
        showWindow()
    }

    @objc private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let candidates = NSApp.windows.filter { window in
            window.styleMask.contains(.titled)
                && window.styleMask.contains(.closable)
                && !(window is NSPanel)
        }
        if let window = candidates.first(where: { $0.isVisible }) ?? candidates.first {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openFallbackWindow()
    }

    private func openFallbackWindow() {
        guard let state else { return }
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: ContentView().environmentObject(state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Force EDID"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 840, height: 560))
        window.minSize = NSSize(width: 760, height: 500)
        window.maxSize = NSSize(width: 1100, height: 780)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = AppDelegate.shared
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
    }

    @objc private func apply() {
        state?.applyAssignedToConnectedDisplays()
    }

    @objc private func refresh() {
        state?.refreshDisplays()
    }

    @objc private func checkUpdates() {
        showWindow()
        state?.checkForUpdatesManual()
    }

    @objc private func openSite() {
        NSWorkspace.shared.open(AppInfo.makerURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
