import Foundation

struct GitHubRelease: Equatable {
    var tag: String
    var version: String
    var htmlURL: URL
    var name: String
}

enum UpdateCheckOutcome: Equatable {
    case upToDate(current: String)
    case updateAvailable(GitHubRelease)
    case failed(String)
}

enum UpdateChecker {
    static let releasesAPI = URL(string: "https://api.github.com/repos/desertdognl/force-edid/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/desertdognl/force-edid/releases")!

    private static let lastWeeklyKey = "updateLastWeeklyCheck"
    private static let dismissedKey = "updateDismissedVersion"

    static var dismissedVersion: String {
        get { UserDefaults.standard.string(forKey: dismissedKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }

    static var lastWeeklyCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastWeeklyKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastWeeklyKey) }
    }

    static func fetchLatest() async -> UpdateCheckOutcome {
        var request = URLRequest(url: releasesAPI, timeoutInterval: 12)
        request.setValue("ForceEDID/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed("GitHub returned HTTP \(http.statusCode).")
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String
            else {
                return .failed("Could not read the GitHub release info.")
            }
            let version = normalizeVersion(tag)
            let html = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
            let name = (json["name"] as? String)?.nilIfEmpty ?? "Force EDID \(version)"
            let release = GitHubRelease(tag: tag, version: version, htmlURL: html, name: name)
            if isVersion(version, greaterThan: AppInfo.displayVersion) {
                return .updateAvailable(release)
            }
            return .upToDate(current: AppInfo.displayVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Monday 09:00 of the current local week. If today is before that moment, returns *last* Monday 09:00.
    static func mostRecentMondayNineAM(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start) // 1 = Sunday … 7 = Saturday
        let daysFromMonday = (weekday + 5) % 7 // Monday → 0
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: start) ?? start
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday) ?? monday
    }

    /// Next Monday 09:00 strictly after `date`.
    static func nextMondayNineAM(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        let thisOrLast = mostRecentMondayNineAM(from: date, calendar: calendar)
        if date < thisOrLast { return thisOrLast }
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: thisOrLast)) ?? date
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMonday) ?? nextMonday
    }

    static func isWeeklyCheckDue(now: Date = Date()) -> Bool {
        let mondayNine = mostRecentMondayNineAM(from: now)
        guard now >= mondayNine else { return false }
        if let last = lastWeeklyCheck, last >= mondayNine { return false }
        return true
    }

    static func markWeeklyCheckDone(at date: Date = Date()) {
        lastWeeklyCheck = date
    }

    static func shouldShow(release: GitHubRelease) -> Bool {
        dismissedVersion != release.version
    }

    static func normalizeVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }

    /// Semver-ish: 1.5.2 > 1.5.1 > 1.5 > 1.4.0
    static func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        let left = numericParts(lhs)
        let right = numericParts(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        normalizeVersion(version)
            .split(separator: ".")
            .map { part in Int(part.filter(\.isNumber)) ?? 0 }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
