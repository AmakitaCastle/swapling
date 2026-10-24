import XCTest
@testable import IslandCore

/// The demo cards are the standard walkthrough tasks; each must land in the state its
/// expectation names, so the material never contradicts the app.
final class DemoScenariosTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func status(_ id: String) -> ProviderStatus? {
        DemoScenarios.all(now: now).first { $0.provider.id == id }.map {
            QuotaOverview.status(of: $0.provider, thresholds: .standard, refreshInterval: 120, now: now)
        }
    }

    private func release(_ id: String) -> LimitRelease? {
        DemoScenarios.all(now: now).first { $0.provider.id == id }.map { QuotaOverview.release(of: $0.provider, now: now) }
    }

    func testScenarioStatesMatchTheirExpectations() {
        XCTAssertEqual(status("codex:正常"), .normal)
        XCTAssertEqual(status("claude:接近上限"), .nearLimit)
        XCTAssertEqual(status("claude:5小时用完"), .limited(partial: false))
        XCTAssertEqual(status("claude:周额度用完"), .limited(partial: false))
        XCTAssertEqual(status("claude:两者用完"), .limited(partial: false))
        XCTAssertEqual(status("claude:仅模型受限"), .limited(partial: true))
        XCTAssertEqual(status("codex:重置时间未知"), .limited(partial: false))
        XCTAssertEqual(status("codex:读取失败沿用"), .unconfirmed)
        XCTAssertEqual(status("openai:未登录"), .unconfirmed)
        XCTAssertEqual(status("deepseek"), .normal)
    }

    func testScenarioReleaseTimes() {
        XCTAssertEqual(release("claude:5小时用完"), .expected(at: now.addingTimeInterval(1.5 * 3600)))
        XCTAssertEqual(release("claude:周额度用完"), .expected(at: now.addingTimeInterval(40 * 3600)))
        XCTAssertEqual(release("claude:两者用完"), .expected(at: now.addingTimeInterval(30 * 3600)))
        guard case .perWindow = release("claude:仅模型受限") else { return XCTFail() }
        guard case .perWindow = release("codex:重置时间未知") else { return XCTFail() }
    }

    func testNormalCardLeadsWithTheSessionWindow() {
        let codex = DemoScenarios.all(now: now).first { $0.provider.id == "codex:正常" }!.provider
        XCTAssertEqual(QuotaOverview.keyWindow(of: codex, thresholds: .standard)?.id, "primary")
    }
}
