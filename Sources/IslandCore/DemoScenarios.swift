import Foundation

/// Fixed quota situations for walkthroughs and screenshots (`--demo`): each card is one standard
/// task, e.g. "which provider is limited, and when does it come back?". Times are relative to `now`.
public enum DemoScenarios {
    public struct Scenario: Sendable {
        /// Card id; the account part names the situation, e.g. "claude:5小时用完".
        public let provider: ProviderUsage
        /// What a reader should be able to say about the card.
        public let expectation: String
    }

    /// One panel state of the character walkthrough (`--demo --demo-characters`).
    public struct CharacterScene: Sendable {
        public let name: String
        public let providers: [ProviderUsage]
    }

    /// Isolated artwork walkthrough, never live provider data: Claude fine, Codex near its limit,
    /// Claude used up (the mascot hands over to Codex), then both used up (asleep until one returns).
    public static func characterScenes(now: Date) -> [CharacterScene] {
        func row(_ id: String, _ used: Double, reset hours: Double) -> ProviderUsage {
            ProviderUsage(id: id, windows: [
                QuotaWindow(id: "primary", title: "Session", usedPercent: used, windowMinutes: 300,
                            resetsAt: now.addingTimeInterval(hours * 3600)),
                QuotaWindow(id: "secondary", title: "Weekly", usedPercent: min(used, 60) * 0.7, windowMinutes: 10080,
                            resetsAt: now.addingTimeInterval(80 * 3600)),
            ], fetchedAt: now)
        }
        return [
            CharacterScene(name: "Claude 正常", providers: [row("claude", 42, reset: 3.2), row("codex", 18, reset: 4)]),
            CharacterScene(name: "Codex 紧张", providers: [row("claude", 42, reset: 3.2), row("codex", 86, reset: 4.0 / 3)]),
            CharacterScene(name: "Claude 用完", providers: [row("claude", 100, reset: 2 + 5.0 / 60), row("codex", 63, reset: 4)]),
            CharacterScene(name: "全部用完", providers: [row("claude", 100, reset: 2 + 5.0 / 60), row("codex", 100, reset: 0.75)]),
        ]
    }

    public static func all(now: Date) -> [Scenario] {
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        func session(_ used: Double, reset hours: Double?) -> QuotaWindow {
            QuotaWindow(id: "primary", title: "Session", usedPercent: used, windowMinutes: 300, resetsAt: hours.map(at))
        }
        func weekly(_ used: Double, reset hours: Double?) -> QuotaWindow {
            QuotaWindow(id: "secondary", title: "Weekly", usedPercent: used, windowMinutes: 10080, resetsAt: hours.map(at))
        }
        func row(_ id: String, _ windows: [QuotaWindow], error: String? = nil, fetchedAt: Date? = nil) -> ProviderUsage {
            ProviderUsage(id: id, windows: windows, error: error, fetchedAt: fetchedAt ?? now)
        }

        return [
            Scenario(
                provider: row("codex:正常", [session(23, reset: 3.5), weekly(41, reset: 80)]),
                expectation: "额度正常；首层为 Session（Weekly 41% 未过提醒线，不顶替）；下一项额度重置为 Session，约 3.5 小时后"
            ),
            Scenario(
                provider: row("claude:接近上限", [session(86, reset: 1.2), weekly(52, reset: 50)]),
                expectation: "接近上限（Session 已过第一条提醒线 80%）；下一项额度重置为 Session"
            ),
            Scenario(
                provider: row("claude:5小时用完", [session(100, reset: 1.5), weekly(64, reset: 70)]),
                expectation: "额度受限；限制预计解除 = Session 的重置时间（约 1.5 小时后）"
            ),
            Scenario(
                provider: row("claude:周额度用完", [session(12, reset: 2), weekly(100, reset: 40)]),
                expectation: "额度受限；下一项重置是 Session（2 小时后），但限制预计解除要等 Weekly（约 40 小时后）"
            ),
            Scenario(
                provider: row("claude:两者用完", [session(100, reset: 0.5), weekly(100, reset: 30)]),
                expectation: "额度受限；限制预计解除取较晚的 Weekly（约 30 小时后），不是 Session 的 0.5 小时"
            ),
            Scenario(
                provider: row("claude:仅模型受限", [
                    session(35, reset: 2),
                    weekly(48, reset: 60),
                    QuotaWindow(id: "extra-opus", title: "Opus", usedPercent: 100, resetsAt: at(20)),
                ]),
                expectation: "部分受限；逐行显示 Opus 已用完（仅此模型）及其重置时间；不给平台整体解除时间"
            ),
            Scenario(
                provider: row("codex:重置时间未知", [session(100, reset: nil), weekly(30, reset: 90)]),
                expectation: "额度受限；Session 显示“重置时间未知”，并说明不推断整体何时恢复"
            ),
            Scenario(
                provider: {
                    var p = row("codex:读取失败沿用", [session(40, reset: 3), weekly(20, reset: 90)],
                                error: "The request timed out.", fetchedAt: now.addingTimeInterval(-1200))
                    p.isCarriedOver = true
                    return p
                }(),
                expectation: "待确认；提示本次读取失败、显示上次的数据；数字变灰；给出“重试”"
            ),
            Scenario(
                provider: row("openai:未登录", [], error: "401 Unauthorized"),
                expectation: "待确认；没有额度数字；给出登录说明和重试"
            ),
            Scenario(
                provider: {
                    var full = ["deepseek": 120.0]
                    let row = ProviderUsage(id: "deepseek", balance: Balance(amount: 86.5, currencyCode: "CNY", parts: [
                        BalancePart(label: "充值", amount: 80), BalancePart(label: "赠送", amount: 6.5),
                    ]), fetchedAt: now)
                    return BalanceGauge.apply([row], baselines: &full)[0]
                }(),
                expectation: "按余额；上次充值后为 ¥120，现余 ¥86.5，进度条剩约 72%；刘海显示金额"
            ),
        ]
    }
}
