import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmApply = false
    @State private var confirmApplyAll = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                displaysColumn
                    .frame(width: 280)
                Divider()
                libraryColumn
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { state.bootstrap() }
        .onAppear { WindowCentering.centerIfNeeded() }
        .alert("Apply this EDID?", isPresented: $confirmApply) {
            Button("Cancel", role: .cancel) {}
            Button("Apply") { state.applyToSelectedDisplay() }
        } message: {
            if let name = state.selectedDisplay?.name, let profile = state.selectedProfile?.name {
                Text("Apply “\(profile)” to \(name) only. The ATEN link may blink while the extender renegotiates.")
            } else {
                Text("The ATEN link may blink while the extender renegotiates. That is expected.")
            }
        }
        .alert("Apply to all displays?", isPresented: $confirmApplyAll) {
            Button("Cancel", role: .cancel) {}
            Button("Apply to all") { state.applyToAllDisplays() }
        } message: {
            if let profile = state.selectedProfile?.name {
                Text("Apply “\(profile)” to every external display. Each link may blink once.")
            } else {
                Text("Every external display will receive this EDID.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            appMark
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text("Force EDID")
                        .font(.headline)
                    Text(AppInfo.versionLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Button {
                    NSWorkspace.shared.open(AppInfo.makerURL)
                } label: {
                    HStack(spacing: 4) {
                        Text("Made by DesertDog")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 8)

            siliconBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var appMark: some View {
        Group {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "display.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var siliconBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(IOAVBridge.isAppleSilicon ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(IOAVBridge.isAppleSilicon ? "Apple Silicon" : "Intel")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: Capsule())
    }

    private var displaysColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Displays", systemImage: "display")
            if state.displays.isEmpty {
                emptyCard(
                    title: "No external display",
                    body: "Connect the ATEN receiver, then Refresh. Built-in screens are ignored."
                )
            } else {
                ForEach(state.displays) { display in
                    displayRow(display)
                }
            }

            HStack(spacing: 8) {
                Button("Refresh") { state.refreshDisplays() }
                Button("Capture EDID") { state.captureCurrent() }
                    .disabled(state.selectedDisplay == nil)
            }
            .controlSize(.regular)

            Text("Each display can have its own EDID. Apply to this display, or the same EDID to all. Capture while the panel is plugged in directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var libraryColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("EDID library", systemImage: "internaldrive")
                Spacer(minLength: 8)
                Button("Import…") { state.importEDIDInteractive() }
                Button("Export…") { state.exportEDIDInteractive() }
                    .disabled(state.selectedProfile == nil)
                Button("Delete", role: .destructive) { state.deleteSelectedProfile() }
                    .disabled(state.selectedProfile?.isPreset != false)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
            .frame(height: 120)

            if let profile = state.selectedProfile, let summary = state.selectedProfileSummary {
                GroupBox("Selected EDID") {
                    VStack(alignment: .leading, spacing: 5) {
                        labeled("Name", profile.name)
                        labeled("Mode", summary.preferredMode)
                        labeled("File", "\(summary.byteCount) bytes · checksum \(summary.checksumOK ? "OK" : "bad")")
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    confirmApply = true
                } label: {
                    Label("Apply to this display", systemImage: "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.selectedProfile == nil || state.selectedDisplay == nil || !IOAVBridge.isAppleSilicon)

                Button("Apply to all") { confirmApplyAll = true }
                    .disabled(state.selectedProfile == nil || state.displays.isEmpty || !IOAVBridge.isAppleSilicon)
            }

            HStack(spacing: 8) {
                Button("Reset this display") { state.resetSelectedDisplay() }
                    .disabled(state.selectedDisplay == nil || !IOAVBridge.isAppleSilicon)
                Button("Reset all") { state.resetAllDisplays() }
                    .disabled(state.displays.isEmpty || !IOAVBridge.isAppleSilicon)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Reapply each display after a drop of", isOn: $state.autoReapply)
                Stepper(value: $state.reapplyAfterDropSeconds, in: 1...30) {
                    Text("\(state.reapplyAfterDropSeconds) s")
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .disabled(!state.autoReapply)
                Toggle(
                    "Menu bar",
                    isOn: Binding(
                        get: { state.keepInMenuBar },
                        set: { state.setKeepInMenuBar($0) }
                    )
                )
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { state.opensAtLogin },
                        set: { state.setOpensAtLogin($0) }
                    )
                )
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            HStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(state.status.text)
                    .font(.caption)
                if let when = state.lastAppliedAt, let name = state.lastAppliedProfileName {
                    Text("· \(name) \(when.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func profileRow(_ profile: EDIDProfile) -> some View {
        let selected = profile.id == state.selectedProfileID
        return Button {
            state.selectProfile(profile.id)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if profile.id == EDIDGenerator.defaultPresetID {
                            badge("DEFAULT")
                        } else if profile.isPreset {
                            badge("PRESET")
                        }
                    }
                    Text(profile.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    private func displayRow(_ display: ExternalDisplay) -> some View {
        let selected = display.id == state.selectedDisplayID
        return Button {
            state.selectDisplay(display.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: state.assignedProfileID(for: display) == nil ? "display" : "lock.display")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(state.assignedProfileName(for: display) ?? "No EDID assigned")
                        .font(.caption)
                        .foregroundStyle(state.assignedProfileID(for: display) == nil ? .secondary : Color.accentColor)
                }
            }
            .padding(8)
            .frame(width: 252, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .font(.caption)
    }

    private func emptyCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 252, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var statusSymbol: String {
        switch state.status {
        case .idle: return "info.circle"
        case .working: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .idle: return .secondary
        case .working: return .accentColor
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
