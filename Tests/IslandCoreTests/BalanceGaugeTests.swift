import XCTest
@testable import IslandCore

final class BalanceGaugeTests: XCTestCase {
    private func row(_ amount: Double, carried: Bool = false) -> ProviderUsage {
        var p = ProviderUsage(id: "deepseek", balance: Balance(amount: amount, currencyCode: "CNY"))
        p.isCarriedOver = carried
        return p
    }

    private func gauge(_ p: ProviderUsage, _ baselines: inout [String: Double]) -> QuotaWindow? {
        BalanceGauge.apply([p], baselines: &baselines)[0].windows.first { $0.isBalanceGauge }
    }

    func testFirstBalanceIsTheFullMarkThenSpendingEmptiesTheBar() throws {
        var baselines: [String: Double] = [:]
        XCTAssertEqual(gauge(row(40), &baselines)?.usedPercent, 0)
        XCTAssertEqual(baselines["deepseek"], 40)
        XCTAssertEqual(try XCTUnwrap(gauge(row(10), &baselines)?.usedPercent), 75, accuracy: 0.001)
        XCTAssertEqual(baselines["deepseek"], 40, "spending never lowers the full mark")
    }

    func testTopUpResetsTheFullMark() {
        var baselines = ["deepseek": 40.0]
        XCTAssertEqual(gauge(row(90), &baselines)?.usedPercent, 0)
        XCTAssertEqual(baselines["deepseek"], 90)
    }

    func testReapplyingDoesNotStackWindowsAndCarriedRowsKeepTheMark() {
        var baselines = ["deepseek": 40.0]
        let once = BalanceGauge.apply([row(20)], baselines: &baselines)
        var again = once
        again[0].isCarriedOver = true
        XCTAssertEqual(BalanceGauge.apply(again, baselines: &baselines)[0].windows.count, 1)
        XCTAssertEqual(baselines["deepseek"], 40)
    }

    func testQuotaProvidersAndEmptyBalancesAreLeftAlone() {
        var baselines: [String: Double] = [:]
        let codex = ProviderUsage(id: "codex", windows: [QuotaWindow(id: "primary", title: "Session", usedPercent: 30)],
                                  balance: Balance(amount: 5, currencyCode: "credits"))
        XCTAssertEqual(BalanceGauge.apply([codex], baselines: &baselines)[0].windows.map(\.id), ["primary"])
        XCTAssertNil(gauge(row(0), &baselines))
        XCTAssertTrue(baselines.isEmpty)
    }
}
