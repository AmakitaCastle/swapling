import XCTest
@testable import IslandCore

final class CollapsedDisplayTests: XCTestCase {
    private func provider(_ id: String, used: Double) -> ProviderUsage {
        ProviderUsage(id: id, windows: [QuotaWindow(id: "primary", title: "Session", usedPercent: used, windowMinutes: 300)])
    }

    func testShortLabels() {
        XCTAssertEqual(QuotaWindow(id: "a", title: "x", usedPercent: 1, windowMinutes: 300).shortLabel, "5h")
        XCTAssertEqual(QuotaWindow(id: "a", title: "x", usedPercent: 1, windowMinutes: 10080).shortLabel, "周")
        XCTAssertEqual(QuotaWindow(id: "a", title: "x", usedPercent: 1, windowMinutes: 43200).shortLabel, "月")
        XCTAssertEqual(QuotaWindow(id: "a", title: "Claude weekly", usedPercent: 1).shortLabel, "周")
        XCTAssertNil(QuotaWindow(id: "a", title: "Opus", usedPercent: 1).shortLabel)
    }

    func testShownPercent() {
        let window = QuotaWindow(id: "a", title: "x", usedPercent: 30)
        XCTAssertEqual(CollapsedDisplay.shownPercent(for: window, showRemaining: false), 30)
        XCTAssertEqual(CollapsedDisplay.shownPercent(for: window, showRemaining: true), 70)
        XCTAssertEqual(CollapsedDisplay.modeLabel(showRemaining: true), "剩余")
        XCTAssertEqual(CollapsedDisplay.modeLabel(showRemaining: false), "已用")
        XCTAssertEqual(CollapsedDisplay.bothPercents(for: window), "已用 30%，剩余 70%")
        // Over-reported usage never shows a negative remainder.
        let over = QuotaWindow(id: "b", title: "x", usedPercent: 130)
        XCTAssertEqual(CollapsedDisplay.shownPercent(for: over, showRemaining: true), 0)
    }

    func testFewProvidersAreAllShown() {
        let pinned = [provider("a", used: 10), provider("b", used: 20)]
        XCTAssertEqual(CollapsedDisplay.visibleProviders(pinned, limit: 2, urgentPercent: 80, page: 3).map(\.id), ["a", "b"])
    }

    func testRotationKeepsPinnedOrder() {
        let pinned = ["a", "b", "c", "d"].map { provider($0, used: 10) }
        let page0 = CollapsedDisplay.visibleProviders(pinned, limit: 2, urgentPercent: 80, page: 0).map(\.id)
        let page1 = CollapsedDisplay.visibleProviders(pinned, limit: 2, urgentPercent: 80, page: 1).map(\.id)
        XCTAssertEqual(page0, ["a", "b"])
        XCTAssertEqual(page1, ["c", "d"])
    }

    func testUrgentProviderStaysVisible() {
        let pinned = [provider("a", used: 10), provider("b", used: 20), provider("c", used: 90)]
        for page in 0..<4 {
            let ids = CollapsedDisplay.visibleProviders(pinned, limit: 2, urgentPercent: 80, page: page).map(\.id)
            XCTAssertTrue(ids.contains("c"))
            XCTAssertEqual(ids.count, 2)
        }
    }
}
