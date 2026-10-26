import Foundation

enum AppInfo {
    static let version = "1.5.2"
    static let build = "16"
    static let maker = "DesertDog"
    static let makerURL = URL(string: "https://desertdog.nl")!
    static let githubReleasesURL = URL(string: "https://github.com/desertdognl/force-edid/releases")!

    static var displayVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? version
    }

    static var displayBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? build
    }

    static var versionLabel: String {
        "v\(displayVersion)"
    }
}
