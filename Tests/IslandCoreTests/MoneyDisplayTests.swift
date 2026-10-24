import XCTest
@testable import IslandCore

final class MoneyDisplayTests: XCTestCase {
    func testUSDStaysUSDByDefault() {
        let result = MoneyDisplay.usd.convert(12.4, from: "USD")
        XCTAssertEqual(result.code, "USD")
        XCTAssertEqual(result.amount, 12.4, accuracy: 0.0001)
    }

    func testUSDConvertsToCNYAtTheChosenRate() {
        let result = MoneyDisplay(currency: .cny, usdToCNY: 7.2).convert(10, from: "USD")
        XCTAssertEqual(result.code, "CNY")
        XCTAssertEqual(result.amount, 72, accuracy: 0.0001)
    }

    func testCNYBalanceConvertsBackToUSD() {
        let result = MoneyDisplay(currency: .usd, usdToCNY: 8).convert(80, from: "cny")
        XCTAssertEqual(result.code, "USD")
        XCTAssertEqual(result.amount, 10, accuracy: 0.0001)
    }

    func testCreditsAndOtherCurrenciesAreLeftAlone() {
        let money = MoneyDisplay(currency: .cny, usdToCNY: 7)
        XCTAssertEqual(money.convert(5, from: "credits").code, "credits")
        XCTAssertEqual(money.convert(5, from: "EUR").amount, 5)
    }

    func testNonPositiveRateFallsBackToDefault() {
        XCTAssertEqual(MoneyDisplay(currency: .cny, usdToCNY: 0).usdToCNY, MoneyDisplay.defaultRate)
    }

    func testFormattedCNYUsesYuanSymbol() {
        XCTAssertTrue(MoneyDisplay(currency: .cny, usdToCNY: 7).format(2).contains("14"))
        XCTAssertTrue(MoneyDisplay(currency: .cny, usdToCNY: 7).format(2).contains("¥"))
    }
}
