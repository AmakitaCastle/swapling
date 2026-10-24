import XCTest
@testable import IslandCore

final class PanelDisplayTests: XCTestCase {
    private func provider(_ id: String, used: Double?, error: String? = nil) -> ProviderUsage {
        let windows = used.map { [QuotaWindow(id: "primary", title: "x", usedPercent: $0)] } ?? []
        return ProviderUsage(id: id, windows: windows, error: error)
    }

    func testUrgentFirstAndErrorsLast() {
        let sorted = PanelDisplay.byUrgency([
            provider("a", used: 10),
            provider("b", used: nil, error: "boom"),
            provider("c", used: 90),
            provider("d", used: 10),
        ])
        XCTAssertEqual(sorted.map(\.id), ["c", "a", "d", "b"])
    }

    func testErrorSummaries() {
        XCTAssertEqual(PanelDisplay.errorSummary("No Claude session key found"), "没有登录，或登录已失效")
        XCTAssertEqual(PanelDisplay.errorSummary("Missing API key for openrouter"), "缺少或无效的 API Key")
        XCTAssertEqual(PanelDisplay.errorSummary("HTTP 429 Too Many Requests"), "请求太频繁，稍后会自动重试")
        XCTAssertEqual(PanelDisplay.errorSummary("weird"), "获取失败")
        XCTAssertEqual(PanelDisplay.errorSummary("没有找到可用的 Claude 登录。在浏览器登录…"), "没有找到可用的 Claude 登录。")
    }

    func testResetTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = ISO8601DateFormatter().date(from: "2026-10-18T02:00:00Z")! // Sun 10:00 Shanghai
        XCTAssertEqual(PanelDisplay.resetTime(now.addingTimeInterval(3600 * 8 + 40 * 60), now: now, calendar: calendar), "今天 18:40")
        XCTAssertEqual(PanelDisplay.resetTime(now.addingTimeInterval(86400), now: now, calendar: calendar), "明天 10:00")
        XCTAssertEqual(PanelDisplay.resetTime(now.addingTimeInterval(86400 * 3), now: now, calendar: calendar), "周三 10:00")
        XCTAssertEqual(PanelDisplay.resetTime(now.addingTimeInterval(86400 * 10), now: now, calendar: calendar), "10月28日 10:00")
    }

    func testAgo() {
        let now = Date()
        XCTAssertEqual(PanelDisplay.ago(now.addingTimeInterval(-20), now: now), "刚刚")
        XCTAssertEqual(PanelDisplay.ago(now.addingTimeInterval(-180), now: now), "3 分钟前")
    }
}

final class RelativeFormatTests: XCTestCase {
    func testRelative() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(IslandFormat.relative(to: now.addingTimeInterval(30 * 3600), now: now), "1天6小时")
        XCTAssertEqual(IslandFormat.relative(to: now.addingTimeInterval(48 * 3600), now: now), "2天")
        XCTAssertEqual(IslandFormat.relative(to: now.addingTimeInterval(90 * 60), now: now), "1小时30分")
        XCTAssertEqual(IslandFormat.relative(to: now.addingTimeInterval(25 * 60), now: now), "25分钟")
        XCTAssertEqual(IslandFormat.relative(to: now.addingTimeInterval(20), now: now), "不到 1 分钟")
    }
}
