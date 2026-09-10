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
    @Published var assignments: [String: String] = [:]

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
    private var isApplying = false
    private var didRecordInitialDisplays = false
    private var knownDisplayIDs: Set<String> = []
    private var lastSeen: [String: ExternalDisplay] = [:]
    private var missingSince: [String: Date] = [:]
    private var dropQualified: Set<String> = []
    private var ignoreUntil: [String: Date] = [:]

    private let assignmentsKey = "displayProfileMap"

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
        assignments = UserDefaults.standard.dictionary(forKey: assignmentsKey) as? [String: String] ?? [:]
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
        for display in displays {
            lastSeen[display.id] = display
            lastSeen[display.name] = display
        }
        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            if let remembered = displays.first(where: { $0.registryPath == lastDisplayPath || $0.name == lastDisplayPath }) {
                selectedDisplayID = remembered.id
            } else {
                selectedDisplayID = displays.first?.id
            }
        }
        if !didRecordInitialDisplays {
            knownDisplayIDs = Set(displays.map(\.id))
            didRecordInitialDisplays = true
        }
    }

    func selectDisplay(_ id: ExternalDisplay.ID?) {
        selectedDisplayID = id
        guard let display = selectedDisplay, let profileID = assignedProfileID(for: display) else { return }
        selectProfile(profileID)
    }

    func assignedProfileID(for display: ExternalDisplay) -> String? {
        if let uuid = display.uuid, let id = assignments[uuid] { return id }
        if let id = assignments[display.id] { return id }
        return assignments[display.name]
    }

    func assignedProfileName(for display: ExternalDisplay) -> String? {
        assignedProfileID(for: display).flatMap { id in profiles.first { $0.id == id }?.name }
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

    func applyToSelectedDisplay() {
        guard let display = selectedDisplay else {
            status = .error("Choose a display first.")
            return
        }
        guard let profile = selectedProfile, let data = profileData(profile) else {
            status = .error("Choose an EDID first.")
            return
        }
        apply(data: data, profile: profile, to: display)
    }

    func applyToAllDisplays() {
        guard let profile = selectedProfile, let data = profileData(profile) else {
            status = .error("Choose an EDID first.")
            return
        }
        apply(data: data, profile: profile, to: nil)
    }

    func applyAssignedToConnectedDisplays() {
        let items: [(ExternalDisplay, EDIDProfile, Data)] = displays.compactMap { display in
            let profileID = assignedProfileID(for: display) ?? (lastProfileID.isEmpty ? nil : lastProfileID)
            guard let profileID,
                  let profile = profiles.first(where: { $0.id == profileID }),
                  let data = EDIDLibrary.shared.data(for: profile)
            else { return nil }
            return (display, profile, data)
        }
        guard !items.isEmpty else {
            applyToAllDisplays()
            return
        }
        let uniqueIDs = Set(items.map(\.1.id))
        if uniqueIDs.count == 1 {
            apply(data: items[0].2, profile: items[0].1, to: nil)
            return
        }
        applyEach(items, reason: "Applied each display’s assigned EDID.")
    }

    func resetSelectedDisplay() {
        reset(display: selectedDisplay, label: selectedDisplay.map { "Reset “\($0.name)”." })
    }

    func resetAllDisplays() {
        reset(display: nil, label: "Reset all external displays.")
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

    private func profileData(_ profile: EDIDProfile) -> Data? {
        selectedProfileBytes ?? EDIDLibrary.shared.data(for: profile)
    }

    private func apply(data: Data, profile: EDIDProfile, to display: ExternalDisplay?, reason: String? = nil) {
        guard !isApplying else { return }
        guard DisplayService.hasExternalDisplay else {
            status = .warning("No external display connected. Nothing was sent — connect the ATEN receiver first.")
            return
        }
        isApplying = true
        status = .working("Injecting “\(profile.name)”… the ATEN link may blink.")
        markIgnore(display)
        do {
            try DisplayService.apply(edid: data, to: display)
            remember(profile: profile, displays: display.map { [$0] } ?? displays)
            lastAppliedAt = Date()
            lastAppliedProfileName = profile.name
            let target = display?.name ?? (displays.count == 1 ? displays[0].name : "all \(displays.count) displays")
            status = .success(reason ?? "Applied “\(profile.name)” to \(target). If the picture drops, wait a second — the extender is renegotiating.")
            scheduleRefresh()
        } catch {
            status = .error(error.localizedDescription)
        }
        isApplying = false
    }

    private func applyEach(_ items: [(ExternalDisplay, EDIDProfile, Data)], reason: String) {
        guard !isApplying else { return }
        guard DisplayService.hasExternalDisplay else {
            status = .warning("No external display connected. Nothing was sent — connect the ATEN receiver first.")
            return
        }
        isApplying = true
        var applied: [String] = []
        var failed: [String] = []
        for (display, profile, data) in items {
            markIgnore(display)
            do {
                try DisplayService.apply(edid: data, to: display)
                remember(profile: profile, displays: [display])
                applied.append("\(display.name) ← \(profile.name)")
            } catch {
                failed.append("\(display.name): \(error.localizedDescription)")
            }
        }
        lastAppliedAt = Date()
        lastAppliedProfileName = applied.joined(separator: ", ")
        if failed.isEmpty {
            status = .success(reason)
        } else if applied.isEmpty {
            status = .error(failed.joined(separator: " "))
        } else {
            status = .warning("Applied to \(applied.joined(separator: "; ")). Failed: \(failed.joined(separator: " "))")
        }
        scheduleRefresh()
        isApplying = false
    }

    private func applyAssigned(to display: ExternalDisplay, reason: String) {
        let profileID = assignedProfileID(for: display) ?? (lastProfileID.isEmpty ? nil : lastProfileID)
        guard let profileID,
              let profile = profiles.first(where: { $0.id == profileID }),
              let data = EDIDLibrary.shared.data(for: profile)
        else { return }
        apply(data: data, profile: profile, to: display, reason: reason)
    }

    private func reset(display: ExternalDisplay?, label: String?) {
        guard !isApplying else { return }
        isApplying = true
        status = .working("Resetting to the display’s original EDID…")
        markIgnore(display)
        do {
            try DisplayService.reset(display: display)
            lastAppliedAt = Date()
            lastAppliedProfileName = "Factory EDID"
            status = .success((label ?? "Reset.") + " The picture may flicker while the link renegotiates.")
            scheduleRefresh()
        } catch {
            status = .error(error.localizedDescription)
        }
        isApplying = false
    }

    private func remember(profile: EDIDProfile, displays: [ExternalDisplay]) {
        lastProfileID = profile.id
        if let first = displays.first {
            lastDisplayPath = first.registryPath
        }
        for display in displays {
            assignments[display.id] = profile.id
            assignments[display.name] = profile.id
            if let uuid = display.uuid {
                assignments[uuid] = profile.id
            }
        }
        UserDefaults.standard.set(assignments, forKey: assignmentsKey)
    }

    private func markIgnore(_ display: ExternalDisplay?) {
        let until = Date().addingTimeInterval(6)
        let targets = display.map { [$0] } ?? displays
        for item in targets {
            ignoreUntil[item.id] = until
            ignoreUntil[item.name] = until
        }
    }

    private func isIgnored(_ key: String, now: Date) -> Bool {
        guard let until = ignoreUntil[key] else { return false }
        if now < until { return true }
        ignoreUntil[key] = nil
        return false
    }

    private func handleScreenChange() {
        let previous = displays
        refreshDisplays()
        let now = Date()
        let currentIDs = Set(displays.map(\.id))

        let gone = previous.filter { !currentIDs.contains($0.id) }
        let appeared = displays.filter { !knownDisplayIDs.contains($0.id) }

        for display in gone where !isIgnored(display.id, now: now) && !isIgnored(display.name, now: now) {
            if missingSince[display.id] == nil {
                missingSince[display.id] = now
                missingSince[display.name] = now
                status = .working("“\(display.name)” dropped. If it stays gone for \(reapplyAfterDropSeconds)s, reconnect will lock its EDID automatically.")
            }
        }

        for display in appeared {
            if isIgnored(display.id, now: now) || isIgnored(display.name, now: now) {
                clearDrop(for: display)
                continue
            }
            let qualified = isQualifiedDrop(display)
            clearDrop(for: display)
            if qualified && autoReapply {
                applyAssigned(
                    to: display,
                    reason: "“\(display.name)” was gone longer than \(reapplyAfterDropSeconds)s — reapplied its locked EDID."
                )
            }
        }

        knownDisplayIDs = currentIDs
        if gone.contains(where: { missingSince[$0.id] != nil }) {
            startDropWatch()
        }
        if missingSince.isEmpty {
            waitingToRelock = false
            secondsDisplayHasBeenGone = 0
        }
    }

    private func isQualifiedDrop(_ display: ExternalDisplay) -> Bool {
        if dropQualified.contains(display.id) || dropQualified.contains(display.name) { return true }
        return dropQualified.contains { key in
            lastSeen[key]?.name == display.name
        }
    }

    private func clearDrop(for display: ExternalDisplay) {
        missingSince[display.id] = nil
        missingSince[display.name] = nil
        dropQualified.remove(display.id)
        dropQualified.remove(display.name)
        if let uuid = display.uuid {
            missingSince[uuid] = nil
            dropQualified.remove(uuid)
        }
    }

    private func startDropWatch() {
        dropWatchTask?.cancel()
        let seconds = max(1, reapplyAfterDropSeconds)
        dropWatchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.refreshDisplays()
            let currentIDs = Set(self.displays.map(\.id))
            let currentNames = Set(self.displays.map(\.name))
            var stillGone: [String] = []
            for (key, _) in self.missingSince {
                let display = self.lastSeen[key]
                let idGone = display.map { !currentIDs.contains($0.id) } ?? !currentIDs.contains(key)
                let nameGone = display.map { !currentNames.contains($0.name) } ?? !currentNames.contains(key)
                if idGone && nameGone {
                    self.dropQualified.insert(key)
                    if let display {
                        self.dropQualified.insert(display.id)
                        self.dropQualified.insert(display.name)
                    }
                    stillGone.append(display?.name ?? key)
                } else {
                    self.missingSince[key] = nil
                }
            }
            if stillGone.isEmpty {
                self.waitingToRelock = false
                self.secondsDisplayHasBeenGone = 0
            } else {
                self.waitingToRelock = true
                self.secondsDisplayHasBeenGone = seconds
                let names = Array(Set(stillGone)).sorted().joined(separator: ", ")
                self.status = .warning("\(names) gone for \(seconds)s. When \(stillGone.count == 1 ? "it returns" : "they return"), the locked EDID will be applied automatically.")
            }
        }
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
