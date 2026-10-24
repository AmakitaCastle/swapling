import XCTest
@testable import IslandCore

final class BalanceTextTests: XCTestCase {
    func testDeepSeekBalanceWindowBecomesABalance() throws {
        let json = Data(#"""
        [{"provider": "deepseek", "source": "api", "rateWindowLabels": {"primary": "Balance"},
          "usage": {"primary": {"usedPercent": 0, "resetDescription": "¥36.94 (Paid: ¥35.75 / Granted: ¥1.18)"},
                    "secondary": null, "updatedAt": "2026-10-22T16:04:09Z"}}]
        """#.utf8)
        let row = try XCTUnwrap(CodexBarParser.parseUsage(json).first)
        XCTAssertTrue(row.windows.isEmpty, "a balance has no percent to show")
        XCTAssertEqual(row.balance, Balance(amount: 36.94, currencyCode: "CNY", parts: [
            BalancePart(label: "充值", amount: 35.75), BalancePart(label: "赠送", amount: 1.18),
        ]))
        XCTAssertEqual(QuotaOverview.status(of: row, thresholds: .standard, refreshInterval: 120, now: try XCTUnwrap(row.updatedAt)), .balance)
    }

    func testDollarAmountsAndThousandsSeparators() {
        XCTAssertEqual(BalanceText.parse("$1,204.50"), Balance(amount: 1204.5, currencyCode: "USD"))
    }

    func testQuotaWindowsAndUnparseableBalancesStayWindows() throws {
        let json = Data(#"""
        [{"provider": "deepseek", "rateWindowLabels": {"primary": "Balance"},
          "usage": {"primary": {"usedPercent": 0, "resetDescription": "unavailable"}}}]
        """#.utf8)
        XCTAssertEqual(try XCTUnwrap(CodexBarParser.parseUsage(json).first).windows.count, 1)
        XCTAssertFalse(BalanceText.isBalanceLabel("Session"))
    }
}
