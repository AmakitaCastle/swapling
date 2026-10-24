import Foundation

/// What went wrong reading quota data, sorted into cases that each have a next step.
public enum DataIssue: Equatable, Sendable {
    /// No provider is turned on, so there is nothing to read.
    case notConfigured
    /// The bundled CodexBar CLI is gone.
    case cliMissing
    /// Not logged in, or the login expired.
    case auth
    case apiKey
    /// The source the provider is set to no longer works.
    case unsupported
    case network
    case timeout
    case rateLimited
    case server
    case toolMissing
    case other

    /// What the user can do about it, most useful first.
    public enum Action: Equatable, Sendable {
        case retry
        case openSettings
        /// Open the provider's own page to sign in, then retry.
        case signIn
        case downloadCLI
    }

    public var summary: String {
        switch self {
        case .notConfigured: return "还没有开启任何平台"
        case .cliMissing: return "找不到内置的数据组件"
        case .auth: return "没有登录，或登录已失效"
        case .apiKey: return "缺少或无效的 API Key"
        case .unsupported: return "当前的登录方式已不再支持"
        case .network: return "网络连接失败"
        case .timeout: return "请求超时"
        case .rateLimited: return "请求太频繁，稍后会自动重试"
        case .server: return "平台服务暂时出错"
        case .toolMissing: return "找不到需要的命令行工具"
        case .other: return "获取失败"
        }
    }

    /// One sentence on what to do next.
    public var hint: String {
        switch self {
        case .notConfigured: return "到 设置 → 平台与 API Key 里开启要监控的平台。"
        case .cliMissing: return "重新安装 Swapling，或下载 CodexBar 命令行工具后在设置里填写路径。"
        case .auth: return "在浏览器或该平台的命令行工具里重新登录，再点「重试」。"
        case .apiKey: return "到 设置 → 平台与 API Key 里填写或更换 API Key。"
        case .unsupported: return "到 设置 → 平台与 API Key 里换一种读取方式，或关闭这个平台。"
        case .network, .timeout: return "检查网络后点「重试」；恢复联网后也会自动重试。"
        case .rateLimited, .server: return "稍后会自动重试，也可以现在点「重试」。"
        case .toolMissing: return "安装该平台的命令行工具后点「重试」。"
        case .other: return "点「详情」查看原始信息，或点「重试」。"
        }
    }

    public var actions: [Action] {
        switch self {
        case .notConfigured: return [.openSettings]
        case .cliMissing: return [.downloadCLI, .openSettings]
        case .auth: return [.signIn, .retry]
        case .apiKey, .unsupported: return [.openSettings, .retry]
        case .network, .timeout, .rateLimited, .server, .toolMissing, .other: return [.retry]
        }
    }

    /// Settings page the "打开设置" button goes to.
    public enum SettingsPage: Equatable, Sendable {
        /// 显示, which also holds the fallback CLI path.
        case display
        /// 平台与 API Key.
        case providers
    }

    public var settingsPage: SettingsPage {
        switch self {
        case .cliMissing: return .display
        default: return .providers
        }
    }

    /// Sorts a provider's or CodexBar's message into a case.
    public static func classify(_ message: String) -> DataIssue {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            // Our own Chinese rewrites.
            if text.contains("api key") { return .apiKey }
            if text.contains("登录") { return .auth }
            if text.contains("超时") { return .timeout }
            if text.contains("网络") { return .network }
            if text.contains("没有读到任何平台") { return .notConfigured }
            if text.contains("codexbar 命令行工具") { return .cliMissing }
            return .other
        }
        let rules: [([String], DataIssue)] = [
            (["api key", "apikey", "api_key"], .apiKey),
            (["no longer support", "not supported", "unsupported"], .unsupported),
            (["session key", "not logged in", "log in", "login", "sign in", "credential", "cookie"], .auth),
            (["401", "403", "unauthorized", "forbidden", "expired", "invalid token"], .auth),
            (["429", "rate limit", "too many requests"], .rateLimited),
            (["timed out", "timeout"], .timeout),
            (["network", "offline", "could not connect", "connection", "internet", "nsurlerrordomain", "dns"], .network),
            (["command not found", "not installed", "executable"], .toolMissing),
            (["500", "502", "503", "504", "server error", "internal error", "unavailable"], .server),
        ]
        for (needles, issue) in rules where needles.contains(where: text.contains) {
            return issue
        }
        return .other
    }

    /// Sorts a whole-refresh failure, where the client's own error cases are known.
    public static func classify(_ error: Error) -> DataIssue {
        if let error = error as? CodexBarClientError {
            switch error {
            case .cliNotFound: return .cliMissing
            case .timedOut: return .timeout
            // Empty output with nothing on stderr: the CLI had no enabled provider to report.
            case let .emptyOutput(stderr) where stderr.isEmpty: return .notConfigured
            case let .emptyOutput(stderr): return classify(stderr)
            case let .commandFailed(message): return classify(message)
            }
        }
        return classify(error.localizedDescription)
    }
}
