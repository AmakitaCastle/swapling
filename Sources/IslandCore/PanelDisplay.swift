import Foundation

/// Decisions behind the expanded panel, kept out of the views so they can be tested.
public enum PanelDisplay {
    /// Closest to running out first; failing providers go to the bottom. Ties keep CodexBar's order.
    public static func byUrgency(_ providers: [ProviderUsage]) -> [ProviderUsage] {
        providers.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if (a.error == nil) != (b.error == nil) { return a.error == nil }
            let usedA = a.tightestWindow?.usedPercent ?? -1
            let usedB = b.tightestWindow?.usedPercent ?? -1
            if usedA != usedB { return usedA > usedB }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    /// One short Chinese line for a provider error; the full text stays available under 详情.
    public static func errorSummary(_ error: String) -> String {
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            // Already Chinese (our own rewrites): keep the first sentence.
            if let end = trimmed.firstIndex(where: { "。！？".contains($0) }) {
                return String(trimmed[...end])
            }
            return trimmed
        }
        return DataIssue.classify(trimmed).summary
    }

    /// The provider's own usage or billing page, for the card's open button.
    public static func usageURL(for providerID: String) -> URL? {
        let base = providerID.split(separator: ":").first.map(String.init) ?? providerID
        let links: [String: String] = [
            "claude": "https://claude.ai/settings/usage",
            "codex": "https://chatgpt.com/codex/settings/usage",
            "openai": "https://platform.openai.com/usage",
            "openrouter": "https://openrouter.ai/settings/credits",
            "cursor": "https://cursor.com/dashboard",
            "copilot": "https://github.com/settings/copilot",
            "deepseek": "https://platform.deepseek.com/usage",
        ]
        return links[base].flatMap(URL.init(string:))
    }

    /// CodexBar's source id in words: "OAuth", "网页登录", …
    public static func sourceLabel(_ source: String?) -> String? {
        guard let source, !source.isEmpty else { return nil }
        switch source.lowercased() {
        case "oauth": return "OAuth"
        case "web": return "网页登录"
        case "cli": return "命令行"
        case "api", "apikey", "api-key": return "API Key"
        case "local": return "本地日志"
        default: return source
        }
    }

    /// "刚刚", "3 分钟前", "2 小时前".
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86400 { return "\(seconds / 3600) 小时前" }
        return "\(seconds / 86400) 天前"
    }

    /// When a window resets, in words: "今天 18:40", "明天 09:00", "周三 18:40", "10月21日 18:40".
    public static func resetTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case 0: return "今天 \(time)"
        case 1: return "明天 \(time)"
        case 2..<7:
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return "\(names[calendar.component(.weekday, from: date) - 1]) \(time)"
        default:
            return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 \(time)"
        }
    }
}
