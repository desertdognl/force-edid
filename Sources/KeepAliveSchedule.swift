import Foundation

enum KeepAliveSchedule {
    /// Next fire after `now`, aligned to a clock time and repeating every `intervalHours`.
    ///
    /// Example: interval 12, at 09:00 → 09:00, 21:00, 09:00…
    /// Example: interval 24, at 09:00 → every day at 09:00.
    static func nextFire(
        after now: Date = Date(),
        intervalHours: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let hours = max(1, min(168, intervalHours))
        let interval = TimeInterval(hours * 3600)
        let h = min(23, max(0, hour))
        let m = min(59, max(0, minute))

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = h
        components.minute = m
        components.second = 0
        guard var anchor = calendar.date(from: components) else {
            return now.addingTimeInterval(interval)
        }

        // Start from the most recent anchor at or before `now`.
        if anchor > now {
            anchor = calendar.date(byAdding: .day, value: -1, to: anchor) ?? anchor
        }

        var next = anchor
        // Cap iterations so a bad clock cannot spin forever.
        for _ in 0..<500 {
            if next > now { return next }
            next = next.addingTimeInterval(interval)
        }
        return now.addingTimeInterval(interval)
    }

    static func timeLabel(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", min(23, max(0, hour)), min(59, max(0, minute)))
    }
}
