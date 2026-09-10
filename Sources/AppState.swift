import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var displays: [ExternalDisplay] = []
    @Published var profiles: [EDIDProfile] = []
    @Published var selectedDisplayID: ExternalDisplay.ID?
    @Published var selectedProfileID: EDIDProfile.ID?
    @Published var status: AppStatus = .idle
    @Published var lastAppliedAt: Date?
    @Published var lastAppliedProfileName: String?

    @AppStorage("autoReapply") var autoReapply = true
    @AppStorage("reapplyAfterDropSeconds") var reapplyAfterDropSeconds = 3
    @AppStorage("keepInMenuBar") var keepInMenuBar = true
    @AppStorage("lastProfileID") var lastProfileID = ""
    @AppStorage("lastDisplayPath") var lastDisplayPath = ""
    @Published private(set) var secondsDisplayHasBeenGone = 0
    @Published private(set) var waitingToRelock = false

    @Published var opensAtLogin = false

    private var dropWatchTask: Task<Void, Never>?
    private var didBootstrap = false
    private var cancellables = Set<AnyCancellable>()
    private var displayMissingSince: Date?
    private var dropQualified = false
    private var ignorePresenceUntil: Date?
    private var isApplying = false

    var selectedDisplay: ExternalDisplay? {
        displays.first { $0.id == selectedDisplayID } ?? displays.first
    }

    var selectedProfile: EDIDProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    @Published var selectedProfileSummary: EDIDSummary?
    @Published var selectedProfileBytes: Data?

    init() {
        let presets = EDIDGenerator.builtInPresets()
        profiles = presets.map(\.0)
        selectedProfileID = EDIDGenerator.defaultPresetID
        if let match = presets.first(where: { $0.0.id == EDIDGenerator.defaultPresetID }) {
            selectedProfileBytes = match.1
            selectedProfileSummary = EDIDParser.summarize(match.1)
        }
        NSLog("ForceEDID: AppState init (no display / DCP / disk in body)")
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        NSLog("ForceEDID: window visible, deferring extra startup work")
        status = .idle

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            NSLog("ForceEDID: loading library from disk")
            reloadLibrary()

            try? await Task.sleep(for: .milliseconds(150))
            NSLog("ForceEDID: listing NSScreens")
            refreshDisplays()
            if displays.isEmpty {
                status = .warning("No external display found. Connect the ATEN receiver, then click Refresh.")
            }

            startWatchingScreens()

            try? await Task.sleep(for: .milliseconds(200))
            NSLog("ForceEDID: reading login item status")
            opensAtLogin = SMAppService.mainApp.status == .enabled
            StatusBarController.shared.sync(from: self, enabled: keepInMenuBar)
            NSLog("ForceEDID: startup done")
        }
    }

    private func startWatchingScreens() {
        guard cancellables.isEmpty else { return }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(750), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleScreenChange()
            }
            .store(in: &cancellables)
    }

    func setKeepInMenuBar(_ enabled: Bool) {
        keepInMenuBar = enabled
        StatusBarController.shared.sync(from: self, enabled: enabled)
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            opensAtLogin = enabled
            status = .success(enabled ? "Force EDID will open at login." : "Removed from login items.")
        } catch {
            status = .error("Could not update login items: \(error.localizedDescription)")
        }
    }

    func refreshDisplays() {
        displays = DisplayService.listExternalDisplays()
        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            if let remembered = displays.first(where: { $0.registryPath == lastDisplayPath }) {
                selectedDisplayID = remembered.id
            } else {
                selectedDisplayID = displays.first?.id
            }
        }
    }

    func reloadLibrary() {
        profiles = EDIDLibrary.shared.loadProfiles()
        if selectedProfileID == nil {
            selectedProfileID = profiles.first(where: { $0.id == lastProfileID })?.id
                ?? profiles.first(where: { $0.id == EDIDGenerator.defaultPresetID })?.id
                ?? profiles.first?.id
        }
        refreshSelectedCache()
    }

    func refreshSelectedCache() {
        guard let profile = selectedProfile else {
            selectedProfileBytes = nil
            selectedProfileSummary = nil
            return
        }
        selectedProfileBytes = EDIDLibrary.shared.data(for: profile)
        selectedProfileSummary = selectedProfileBytes.map(EDIDParser.summarize)
    }

    func selectProfile(_ id: EDIDProfile.ID?) {
        guard id != selectedProfileID else { return }
        selectedProfileID = id
        refreshSelectedCache()
    }

    func importEDIDInteractive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]
        panel.title = "Import EDID"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importEDID(from: url)
        refreshSelectedCache()
    }

    func exportEDIDInteractive() {
        guard let profile = selectedProfile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "\(profile.name).bin"
        panel.title = "Export EDID"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportSelected(to: url)
    }

    func applySelected() {
        guard let profile = selectedProfile else {
            status = .error("Choose an EDID first.")
            return
        }
        let data = selectedProfileBytes ?? EDIDLibrary.shared.data(for: profile)
        guard let data else {
            status = .error("Choose an EDID first.")
            return
        }
        apply(data: data, profile: profile)
    }

    func resetSelected() {
        guard !isApplying else { return }
        isApplying = true
        status = .working("Resetting to the display’s original EDID…")
        ignorePresenceUntil = Date().addingTimeInterval(6)
        do {
            try DisplayService.reset(display: selectedDisplay)
            lastAppliedAt = Date()
            lastAppliedProfileName = "Factory EDID"
            status = .success("Reset. The picture may flicker while the link renegotiates.")
            scheduleRefresh()
        } catch {
            status = .error(error.localizedDescription)
        }
        isApplying = false
    }

    func captureCurrent() {
        guard let display = selectedDisplay else {
            status = .error("No external display to capture.")
            return
        }
        do {
            let data = try DisplayService.captureEDID(from: display)
            let summary = EDIDParser.summarize(data)
            let profile = try EDIDLibrary.shared.saveCapture(
                data,
                name: summary.productName == "Unnamed display" ? "Captured \(formattedNow())" : summary.productName,
                note: "Captured from \(display.name) on \(formattedNow())."
            )
            reloadLibrary()
            selectedProfileID = profile.id
            status = .success("Saved “\(profile.name)”. If this was through the ATEN, capture again with the display plugged in directly for a cleaner lock.")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func importEDID(from url: URL) {
        do {
            let profile = try EDIDLibrary.shared.importFile(from: url, suggestedName: nil)
            reloadLibrary()
            selectedProfileID = profile.id
            status = .success("Imported “\(profile.name)”.")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func deleteSelectedProfile() {
        guard let profile = selectedProfile, !profile.isPreset else { return }
        EDIDLibrary.shared.delete(profile)
        selectedProfileID = nil
        reloadLibrary()
        status = .success("Removed “\(profile.name)” from the library.")
    }

    func exportSelected(to url: URL) {
        guard let profile = selectedProfile else { return }
        do {
            try EDIDLibrary.shared.export(profile, to: url)
            status = .success("Exported \(url.lastPathComponent).")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func apply(data: Data, profile: EDIDProfile, reason: String? = nil) {
        guard !isApplying else { return }
        guard DisplayService.hasExternalDisplay else {
            status = .warning("No external display connected. Nothing was sent — connect the ATEN receiver first.")
            return
        }
        isApplying = true
        status = .working("Injecting “\(profile.name)”… the ATEN link may blink.")
        ignorePresenceUntil = Date().addingTimeInterval(6)
        do {
            try DisplayService.apply(edid: data, to: nil)
            lastProfileID = profile.id
            lastDisplayPath = selectedDisplay?.registryPath ?? lastDisplayPath
            lastAppliedAt = Date()
            lastAppliedProfileName = profile.name
            status = .success(reason ?? "Applied “\(profile.name)”. If the picture drops, wait a second — the extender is renegotiating.")
            scheduleRefresh()
        } catch {
            status = .error(error.localizedDescription)
        }
        isApplying = false
    }

    private func applyLastUsed(reason: String) {
        guard let profile = profiles.first(where: { $0.id == lastProfileID }),
              let data = EDIDLibrary.shared.data(for: profile)
        else { return }
        apply(data: data, profile: profile, reason: reason)
    }

    private func handleScreenChange() {
        refreshDisplays()
        let present = DisplayService.hasExternalDisplay
        let now = Date()
        if let ignorePresenceUntil, now < ignorePresenceUntil {
            if present { clearDropWatch() }
            return
        }

        if present {
            let shouldRelock = dropQualified && autoReapply && !lastProfileID.isEmpty
            clearDropWatch()
            if shouldRelock {
                applyLastUsed(reason: "Display was gone longer than \(reapplyAfterDropSeconds)s — reapplied the locked EDID.")
            }
            return
        }

        // No external screen: never talk to DCP. Just remember that a drop happened.
        guard autoReapply, !lastProfileID.isEmpty else { return }

        if displayMissingSince == nil {
            displayMissingSince = now
            secondsDisplayHasBeenGone = 0
            waitingToRelock = false
            dropQualified = false
            status = .working("Display dropped. If it stays gone for \(reapplyAfterDropSeconds)s, the next reconnect will lock EDID automatically.")
            startDropWatch()
        }
    }

    private func startDropWatch() {
        dropWatchTask?.cancel()
        let seconds = max(1, reapplyAfterDropSeconds)
        dropWatchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.refreshDisplays()
            if self.displays.isEmpty {
                self.dropQualified = true
                self.waitingToRelock = true
                self.secondsDisplayHasBeenGone = seconds
                self.status = .warning("Display has been gone for \(seconds)s. When it returns, the last EDID will be applied automatically.")
            } else {
                self.clearDropWatch()
            }
        }
    }

    private func clearDropWatch() {
        dropWatchTask?.cancel()
        dropWatchTask = nil
        displayMissingSince = nil
        dropQualified = false
        waitingToRelock = false
        secondsDisplayHasBeenGone = 0
    }

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            refreshDisplays()
        }
    }

    private func formattedNow() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
