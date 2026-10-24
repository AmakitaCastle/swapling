import XCTest
@testable import IslandCore

final class QuotaThresholdsTests: XCTestCase {
    func testLevels() {
        let t = QuotaThresholds(warn1: 70, warn2: 90)
        XCTAssertEqual(t.level(forUsed: 0), .normal)
        XCTAssertEqual(t.level(forUsed: 69.9), .normal)
        XCTAssertEqual(t.level(forUsed: 70), .warning)
        XCTAssertEqual(t.level(forUsed: 90), .critical)
        XCTAssertEqual(t.level(forUsed: 100), .exhausted)
        XCTAssertEqual(t.level(for: nil), .unknown)
    }

    func testCustomLinesDriveColourGlowAndAlertsAlike() {
        let t = QuotaThresholds(warn1: 60, warn2: 75)
        XCTAssertEqual(t.alertLevels, [60, 75])
        XCTAssertTrue(t.glows(used: 75))
        XCTAssertFalse(t.glows(used: 74))
        XCTAssertFalse(t.glows(used: 100))

        // The alert engine fires exactly where the colour changes.
        var engine = AlertEngine(thresholds: t.alertLevels)
        let window = QuotaWindow(id: "primary", title: "5 小时", usedPercent: 61)
        let events = engine.process([ProviderUsage(id: "claude", windows: [window])])
        XCTAssertEqual(events, [.threshold(providerID: "claude", window: window, level: 60)])
        XCTAssertEqual(t.level(for: window), .warning)
    }

    func testInvalidPairsAreRepaired() {
        let swapped = QuotaThresholds(warn1: 95, warn2: 80)
        XCTAssertLessThan(swapped.warn1, swapped.warn2)
        XCTAssertEqual(swapped.warn2, 80)

        let equal = QuotaThresholds(warn1: 90, warn2: 90)
        XCTAssertEqual(equal.warn1, 89)
        XCTAssertEqual(equal.warn2, 90)

        let outOfRange = QuotaThresholds(warn1: 0, warn2: 200)
        XCTAssertEqual(outOfRange.warn1, 50)
        XCTAssertEqual(outOfRange.warn2, 99)

        let bothLow = QuotaThresholds(warn1: 50, warn2: 50)
        XCTAssertEqual(bothLow.warn1, 50)
        XCTAssertEqual(bothLow.warn2, 51)
    }

    func testValidity() {
        XCTAssertTrue(QuotaThresholds.isValid(warn1: 80, warn2: 95))
        XCTAssertFalse(QuotaThresholds.isValid(warn1: 95, warn2: 95))
        XCTAssertFalse(QuotaThresholds.isValid(warn1: 96, warn2: 95))
        XCTAssertFalse(QuotaThresholds.isValid(warn1: 40, warn2: 95))
    }
}
