import Foundation

public enum IslandFormat {
    /// "2:14:05" under a day, "3天 4小时" beyond.
    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Short relative form for compact spaces: "2h", "35m", "3d".
    public static func shortCountdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        if seconds >= 3600 { return "\(seconds / 3600)h" }
        return "\(max(1, seconds / 60))m"
    }

    /// Readable wait for reset lines: "1天6小时", "2小时5分", "25分钟", "不到 1 分钟".
    public static func relative(to date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now))) / 60
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天" }
        if hours > 0 { return mins > 0 ? "\(hours)小时\(mins)分" : "\(hours)小时" }
        return minutes > 0 ? "\(minutes)分钟" : "不到 1 分钟"
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func money(_ amount: Double, currencyCode: String = "USD") -> String {
        if currencyCode == "credits" {
            return String(format: "%.1f credits", amount)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = amount < 10 ? 2 : 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}
