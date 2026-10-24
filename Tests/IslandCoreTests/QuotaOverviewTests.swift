import XCTest
@testable import IslandCore

final class QuotaOverviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let t = QuotaThresholds.standard

    private func session(_ used: Double, resetIn: TimeInterval? = 3600) -> QuotaWindow {
        QuotaWindow(id: "primary", title: "Session", usedPercent: used, windowMinutes: 300,
                    resetsAt: resetIn.map { now.addingTimeInterval($0) })
    }

    private func weekly(_ used: Double, resetIn: TimeInterval? = 86400 * 3) -> QuotaWindow {
        QuotaWindow(id: "secondary", title: "Weekly", usedPercent: used, windowMinutes: 10080,
                    resetsAt: resetIn.map { now.addingTimeInterval($0) })
    }

    private func opus(_ used: Double, resetIn: TimeInterval? = 86400) -> QuotaWindow {
        QuotaWindow(id: "extra-opus", title: "Opus", usedPercent: used,
                    resetsAt: resetIn.map { now.addingTimeInterval($0) })
    }

    private func provider(_ windows: [QuotaWindow], error: String? = nil, fetchedAt: Date? = nil) -> ProviderUsage {
        ProviderUsage(id: "claude", windows: windows, error: error, fetchedAt: fetchedAt ?? now)
    }

    private func status(_ p: ProviderUsage) -> ProviderStatus {
        QuotaOverview.status(of: p, thresholds: t, refreshInterval: 120, now: now)
    }

    // MARK: Status

    func testStatuses() {
        XCTAssertEqual(status(provider([session(10), weekly(20)])), .normal)
        XCTAssertEqual(status(provider([session(85), weekly(20)])), .nearLimit)
        XCTAssertEqual(status(provider([session(100), weekly(20)])), .limited(partial: false))
        XCTAssertEqual(status(provider([session(10), opus(100)])), .limited(partial: true))
        XCTAssertEqual(ProviderStatus.limited(partial: false).label, "额度受限")
        XCTAssertEqual(ProviderStatus.unconfirmed.label, "待确认")
    }

    func testStaleAndErrorsWinOverNumbers() {
        // Used up but the numbers are old: 待确认, never 额度受限 or 额度正常 on stale data.
        XCTAssertEqual(status(provider([session(100)], fetchedAt: now.addingTimeInterval(-3600))), .unconfirmed)
        XCTAssertEqual(status(provider([session(10)], error: "401 Unauthorized")), .unconfirmed)
        XCTAssertEqual(status(ProviderUsage(id: "x")), .unconfirmed)
    }

    func testBalanceProvidersKeepTheirOwnSemantics() {
        var p = ProviderUsage(id: "openrouter", balance: Balance(amount: 4.2, currencyCode: "USD"), fetchedAt: now)
        p.windows = []
        XCTAssertEqual(status(p), .balance)
    }

    // MARK: Reset vs release

    func testFiveHourExhausted() {
        let p = provider([session(100, resetIn: 3600), weekly(40)])
        XCTAssertEqual(QuotaOverview.release(of: p, now: now), .expected(at: now.addingTimeInterval(3600)))
        XCTAssertEqual(QuotaOverview.keyWindow(of: p)?.id, "primary")
        XCTAssertEqual(QuotaOverview.nextReset(of: p, now: now)?.window.id, "primary")
    }

    func testWeeklyExhaustedOutlastsTheSessionReset() {
        let p = provider([session(30, resetIn: 3600), weekly(100, resetIn: 86400 * 3)])
        // The next reset is the session window, but that doesn't lift the limit.
        XCTAssertEqual(QuotaOverview.nextReset(of: p, now: now)?.window.id, "primary")
        XCTAssertEqual(QuotaOverview.release(of: p, now: now), .expected(at: now.addingTimeInterval(86400 * 3)))
        XCTAssertEqual(QuotaOverview.keyWindow(of: p)?.id, "secondary")
    }

    func testBothExhaustedReleaseAtTheLaterReset() {
        let p = provider([session(100, resetIn: 3600), weekly(100, resetIn: 86400 * 2)])
        XCTAssertEqual(QuotaOverview.release(of: p, now: now), .expected(at: now.addingTimeInterval(86400 * 2)))
        XCTAssertEqual(QuotaOverview.keyWindow(of: p)?.id, "secondary")
        XCTAssertEqual(status(p), .limited(partial: false))
    }

    func testModelScopedLimitIsNeverAProviderWideRelease() {
        let p = provider([session(20), weekly(30), opus(100, resetIn: 86400)])
        guard case let .perWindow(resets) = QuotaOverview.release(of: p, now: now) else {
            return XCTFail("model-scoped limits must be listed per window")
        }
        XCTAssertEqual(resets.map(\.window.id), ["extra-opus"])
        XCTAssertEqual(resets.first?.resetsAt, now.addingTimeInterval(86400))
    }

    func testModelScopedPlusProviderWideStaysPerWindow() {
        let p = provider([session(100, resetIn: 3600), opus(100, resetIn: 86400)])
        guard case let .perWindow(resets) = QuotaOverview.release(of: p, now: now) else {
            return XCTFail("mixed scopes must not be merged into one time")
        }
        XCTAssertEqual(resets.map(\.window.id), ["primary", "extra-opus"])
        XCTAssertEqual(QuotaOverview.keyWindow(of: p)?.id, "primary", "the provider-wide limit is the key one")
    }

    func testUnknownResetTimeIsNotGuessed() {
        let p = provider([session(100, resetIn: nil), weekly(20)])
        XCTAssertEqual(QuotaOverview.release(of: p, now: now), .perWindow([WindowReset(window: p.windows[0], resetsAt: nil)]))
        // A reset time already in the past is unknown too: the numbers haven't caught up.
        let past = provider([session(100, resetIn: -60)])
        XCTAssertEqual(QuotaOverview.release(of: past, now: now), .perWindow([WindowReset(window: past.windows[0], resetsAt: nil)]))
    }

    func testOneWindowResettingDoesNotClearTheOther() {
        // After the session window resets, the still-exhausted weekly window keeps the limit.
        let p = provider([session(0, resetIn: 18000), weekly(100, resetIn: 86400)])
        XCTAssertEqual(status(p), .limited(partial: false))
        XCTAssertEqual(QuotaOverview.release(of: p, now: now), .expected(at: now.addingTimeInterval(86400)))
    }

    func testModelScopeDetection() {
        XCTAssertTrue(opus(1).isModelScoped)
        XCTAssertTrue(QuotaWindow(id: "tertiary", title: "Sonnet weekly", usedPercent: 1).isModelScoped)
        XCTAssertFalse(session(1).isModelScoped)
        XCTAssertFalse(weekly(1).isModelScoped)
    }

    // MARK: Order

    func testAttentionOrder() {
        let providers = [
            ProviderUsage(id: "ok", windows: [session(10)], fetchedAt: now),
            ProviderUsage(id: "broken", error: "x"),
            ProviderUsage(id: "full", windows: [session(100)], fetchedAt: now),
            ProviderUsage(id: "near", windows: [session(90)], fetchedAt: now),
        ]
        let attention = PanelOrder.ids(for: providers, mode: .attention, status: status)
        XCTAssertEqual(attention, ["full", "near", "ok", "broken"])
        XCTAssertEqual(PanelOrder.ids(for: providers, mode: .fixed, status: status), ["ok", "broken", "full", "near"])
    }

    func testOrderStaysPutWhileOpen() {
        let snapshot = ["a", "b", "c"]
        // c became the most urgent and d appeared during a refresh; b went away.
        let refreshed = [ProviderUsage(id: "d"), ProviderUsage(id: "c"), ProviderUsage(id: "a")]
        XCTAssertEqual(PanelOrder.arrange(refreshed, snapshot: snapshot).map(\.id), ["a", "c", "d"])
    }
}

final class DisplayWindowTests: XCTestCase {
    private let t = QuotaThresholds.standard
    private func w(_ id: String, _ used: Double, minutes: Int?, resetIn: TimeInterval? = 3600) -> QuotaWindow {
        QuotaWindow(id: id, title: id, usedPercent: used, windowMinutes: minutes,
                    resetsAt: resetIn.map { Date(timeIntervalSince1970: 0).addingTimeInterval($0) })
    }
    private func shown(_ windows: [QuotaWindow]) -> String? {
        QuotaOverview.displayWindow(of: ProviderUsage(id: "claude", windows: windows), thresholds: t)?.id
    }

    func testSessionWindowByDefaultEvenWhenWeeklyIsMoreUsed() {
        // The case behind the question: Claude 5h 4%, weekly 14% used. Show 5h, not weekly.
        XCTAssertEqual(shown([w("primary", 4, minutes: 300), w("secondary", 14, minutes: 10080)]), "primary")
        XCTAssertEqual(shown([w("primary", 2, minutes: 300), w("secondary", 0, minutes: 10080)]), "primary")
        // A tie stays on 5h.
        XCTAssertEqual(shown([w("primary", 16, minutes: 300), w("secondary", 16, minutes: 10080)]), "primary")
    }

    func testWeeklyTakesOverOnlyPastTheFirstWarningLine() {
        XCTAssertEqual(shown([w("primary", 30, minutes: 300), w("secondary", 79, minutes: 10080)]), "primary")
        XCTAssertEqual(shown([w("primary", 30, minutes: 300), w("secondary", 80, minutes: 10080)]), "secondary")
        // Past the line but the session window is even tighter: stay on 5h.
        XCTAssertEqual(shown([w("primary", 90, minutes: 300), w("secondary", 85, minutes: 10080)]), "primary")
        // Follows the user's own line.
        let low = QuotaThresholds(warn1: 60, warn2: 90)
        let p = ProviderUsage(id: "c", windows: [w("primary", 10, minutes: 300), w("secondary", 65, minutes: 10080)])
        XCTAssertEqual(QuotaOverview.displayWindow(of: p, thresholds: low)?.id, "secondary")
    }

    func testUsedUpWindowWins() {
        XCTAssertEqual(shown([w("primary", 20, minutes: 300), w("secondary", 100, minutes: 10080)]), "secondary")
        XCTAssertEqual(shown([w("primary", 100, minutes: 300), w("secondary", 50, minutes: 10080)]), "primary")
    }

    func testModelWindowsStayOffTheNotchUnlessAlone() {
        let opus = QuotaWindow(id: "extra-opus", title: "Opus", usedPercent: 100)
        XCTAssertEqual(shown([w("primary", 20, minutes: 300), opus]), "primary")
        XCTAssertEqual(shown([opus]), "extra-opus")
    }

    func testWithoutAPrimaryLaneTheShortestWindowLeads() {
        XCTAssertEqual(shown([w("secondary", 50, minutes: 10080), w("daily", 10, minutes: 1440)]), "daily")
    }
}
