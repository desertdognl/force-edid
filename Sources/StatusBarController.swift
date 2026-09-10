import AppKit

@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    private var item: NSStatusItem?
    private weak var state: AppState?

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
        menu.addItem(withTitle: "Show Force EDID", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Apply last EDID", action: #selector(apply), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh displays", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
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

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func apply() {
        state?.applySelected()
    }

    @objc private func refresh() {
        state?.refreshDisplays()
    }

    @objc private func openSite() {
        NSWorkspace.shared.open(AppInfo.makerURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
