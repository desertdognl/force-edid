import Foundation

enum AppInfo {
    static let version = "1.3.0"
    static let build = "12"
    static let maker = "DesertDog"
    static let makerURL = URL(string: "https://desertdog.nl")!

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
