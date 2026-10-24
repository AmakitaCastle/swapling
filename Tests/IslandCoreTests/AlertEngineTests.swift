import XCTest
@testable import IslandCore

final class AlertEngineTests: XCTestCase {
    private func snapshot(_ used: Double, resetsAt: Date? = nil) -> [ProviderUsage] {
        [ProviderUsage(id: "claude", windows: [
            QuotaWindow(id: "primary", title: "5 小时", usedPercent: used, windowMinutes: 300, resetsAt: resetsAt),
        ])]
    }

    private func kinds(_ events: [IslandEvent]) -> [String] {
        events.map {
            switch $0 {
            case let .threshold(_, _, level): return "t\(level)"
            case .exhausted: return "exhausted"
            case .reset: return "reset"
            }
        }
    }

    func testEachThresholdFiresOnce() {
        var engine = AlertEngine(thresholds: [80, 95])
        XCTAssertEqual(kinds(engine.process(snapshot(50))), [])
        XCTAssertEqual(kinds(engine.process(snapshot(81))), ["t80"])
        XCTAssertEqual(kinds(engine.process(snapshot(85))), [])
        XCTAssertEqual(kinds(engine.process(snapshot(96))), ["t95"])
        XCTAssertEqual(kinds(engine.process(snapshot(97))), [])
    }

    func testJumpingPastBothFiresOnlyTheHigher() {
        var engine = AlertEngine(thresholds: [80, 95])
        XCTAssertEqual(kinds(engine.process(snapshot(97))), ["t95"])
    }

    func testExhaustedThenReset() {
        var engine = AlertEngine(thresholds: [80, 95])
        XCTAssertEqual(kinds(engine.process(snapshot(90))), ["t80"])
        XCTAssertEqual(kinds(engine.process(snapshot(100))), ["exhausted"])
        XCTAssertEqual(kinds(engine.process(snapshot(100))), [])
        XCTAssertEqual(kinds(engine.process(snapshot(3))), ["reset"])
        // New period: thresholds are armed again.
        XCTAssertEqual(kinds(engine.process(snapshot(82))), ["t80"])
    }

    func testDroppingBelowThresholdRearms() {
        var engine = AlertEngine(thresholds: [80, 95])
        XCTAssertEqual(kinds(engine.process(snapshot(85))), ["t80"])
        XCTAssertEqual(kinds(engine.process(snapshot(10))), [])
        XCTAssertEqual(kinds(engine.process(snapshot(85))), ["t80"])
    }

    func testFailedProvidersAreIgnored() {
        var engine = AlertEngine()
        var failing = snapshot(99)
        failing[0].error = "boom"
        XCTAssertEqual(engine.process(failing), [])
    }

    func testCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(IslandFormat.countdown(to: now.addingTimeInterval(8045), now: now), "2:14:05")
        XCTAssertEqual(IslandFormat.countdown(to: now.addingTimeInterval(65), now: now), "01:05")
        XCTAssertEqual(IslandFormat.countdown(to: now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now), "3天 4小时")
        XCTAssertEqual(IslandFormat.shortCountdown(to: now.addingTimeInterval(7300), now: now), "2h")
    }
}
