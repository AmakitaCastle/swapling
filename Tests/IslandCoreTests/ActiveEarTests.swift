import XCTest
@testable import IslandCore

final class ActiveEarTests: XCTestCase {
    private func row(_ id: String, _ used: Double) -> ProviderUsage {
        ProviderUsage(id: id, windows: [QuotaWindow(id: "primary", title: "Session", usedPercent: used)])
    }

    func testActiveIDMatchesAccountRows() {
        let rows = [row("codex", 10), row("claude:work", 20)]
        XCTAssertEqual(CollapsedDisplay.activeID(in: rows, activeProviderID: "claude"), "claude:work")
        XCTAssertEqual(CollapsedDisplay.activeID(in: rows, activeProviderID: "codex"), "codex")
        XCTAssertNil(CollapsedDisplay.activeID(in: rows, activeProviderID: "gemini"))
        XCTAssertNil(CollapsedDisplay.activeID(in: rows, activeProviderID: nil))
    }

    func testAlreadyShownActiveChangesNothing() {
        let shown = [row("claude", 10), row("codex", 20)]
        let result = CollapsedDisplay.withActive(shown, candidates: shown + [row("gemini", 5)],
                                                 activeProviderID: "codex", limit: 2, urgentPercent: 80)
        XCTAssertEqual(result.map(\.id), ["claude", "codex"])
    }

    func testFreeSlotTakesTheActiveProvider() {
        let result = CollapsedDisplay.withActive([row("claude", 10)], candidates: [row("claude", 10), row("codex", 20)],
                                                 activeProviderID: "codex", limit: 2, urgentPercent: 80)
        XCTAssertEqual(result.map(\.id), ["claude", "codex"])
    }

    func testActiveReplacesTheLastNonUrgentItemInCandidateOrder() {
        let candidates = [row("claude", 10), row("gemini", 30), row("codex", 20), row("deepseek", 90)]
        let shown = [row("claude", 10), row("gemini", 30)]
        let result = CollapsedDisplay.withActive(shown, candidates: candidates, activeProviderID: "codex",
                                                 limit: 2, urgentPercent: 80)
        XCTAssertEqual(result.map(\.id), ["claude", "codex"])
    }

    func testUrgentItemsAreNeverDisplaced() {
        let shown = [row("claude", 85), row("gemini", 95)]
        let result = CollapsedDisplay.withActive(shown, candidates: shown + [row("codex", 10)],
                                                 activeProviderID: "codex", limit: 2, urgentPercent: 80)
        XCTAssertEqual(result.map(\.id), ["claude", "gemini"])
        let mixed = [row("claude", 85), row("gemini", 20)]
        XCTAssertEqual(CollapsedDisplay.withActive(mixed, candidates: mixed + [row("codex", 10)],
                                                   activeProviderID: "codex", limit: 2, urgentPercent: 80).map(\.id),
                       ["claude", "codex"])
    }

    func testUnknownActiveChangesNothing() {
        let shown = [row("claude", 10)]
        XCTAssertEqual(CollapsedDisplay.withActive(shown, candidates: shown, activeProviderID: "codex",
                                                   limit: 2, urgentPercent: 80).map(\.id), ["claude"])
    }

    func testSweepStepsAcrossThenRests() {
        let cells = (0..<14).map { CollapsedDisplay.sweepCell(tick: $0, cells: 8, pause: 6) }
        XCTAssertEqual(cells, [0, 1, 2, 3, 4, 5, 6, 7, nil, nil, nil, nil, nil, nil])
        XCTAssertEqual(CollapsedDisplay.sweepCell(tick: 14, cells: 8, pause: 6), 0)
        XCTAssertEqual(CollapsedDisplay.sweepCell(tick: -1, cells: 8, pause: 6), nil)
        XCTAssertNil(CollapsedDisplay.sweepCell(tick: 3, cells: 0))
    }
}
