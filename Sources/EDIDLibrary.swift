import Foundation

final class EDIDLibrary {
    static let shared = EDIDLibrary()

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let profilesURL: URL
    private let filesURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        rootURL = appSupport.appendingPathComponent("Force EDID", isDirectory: true)
        profilesURL = rootURL.appendingPathComponent("profiles.json")
        filesURL = rootURL.appendingPathComponent("edids", isDirectory: true)
        try? fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)
    }

    func loadProfiles() -> [EDIDProfile] {
        seedPresetsIfNeeded()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: profilesURL),
              let profiles = try? decoder.decode([EDIDProfile].self, from: data)
        else {
            return []
        }
        return profiles.sorted { lhs, rhs in
            if lhs.id == EDIDGenerator.defaultPresetID { return true }
            if rhs.id == EDIDGenerator.defaultPresetID { return false }
            if lhs.isPreset != rhs.isPreset { return lhs.isPreset && !rhs.isPreset }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func data(for profile: EDIDProfile) -> Data? {
        let url = filesURL.appendingPathComponent(profile.filename)
        return try? Data(contentsOf: url)
    }

    func importFile(from source: URL, suggestedName: String?) throws -> EDIDProfile {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: source)
        guard EDIDParser.isValid(data) else { throw ForceEDIDError.invalidEDID }

        let summary = EDIDParser.summarize(data)
        let name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? summary.productName
        return try store(
            data: data,
            name: name,
            note: "Imported from \(source.lastPathComponent)",
            isPreset: false
        )
    }

    func saveCapture(_ data: Data, name: String, note: String) throws -> EDIDProfile {
        guard EDIDParser.isValid(data) || data.count >= 128 else { throw ForceEDIDError.invalidEDID }
        return try store(data: data, name: name, note: note, isPreset: false)
    }

    func rename(_ profile: EDIDProfile, to name: String) {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }), !profiles[index].isPreset else { return }
        profiles[index].name = name
        save(profiles)
    }

    func delete(_ profile: EDIDProfile) {
        guard !profile.isPreset else { return }
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == profile.id }
        save(profiles)
        try? fileManager.removeItem(at: filesURL.appendingPathComponent(profile.filename))
    }

    func export(_ profile: EDIDProfile, to destination: URL) throws {
        guard let data = data(for: profile) else { throw ForceEDIDError.cannotReadFile }
        try data.write(to: destination)
    }

    private func store(data: Data, name: String, note: String, isPreset: Bool) throws -> EDIDProfile {
        let id = isPreset ? name : UUID().uuidString
        let filename = isPreset ? "\(id).bin" : "\(id).bin"
        let profile = EDIDProfile(
            id: id,
            name: name,
            note: note,
            isPreset: isPreset,
            createdAt: Date(),
            filename: filename
        )
        try data.write(to: filesURL.appendingPathComponent(filename), options: .atomic)
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        save(profiles)
        return profile
    }

    private func seedPresetsIfNeeded() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let existing = (try? Data(contentsOf: profilesURL)).flatMap {
            try? decoder.decode([EDIDProfile].self, from: $0)
        } ?? []

        let userProfiles = existing.filter { !$0.isPreset }
        let presets = EDIDGenerator.builtInPresets()
        for (preset, data) in presets {
            try? data.write(to: filesURL.appendingPathComponent(preset.filename), options: .atomic)
        }
        save(presets.map(\.0) + userProfiles)
    }

    private func save(_ profiles: [EDIDProfile]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: profilesURL, options: .atomic)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
