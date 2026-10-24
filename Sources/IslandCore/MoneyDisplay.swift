import Foundation

/// Currency the panel shows amounts in.
public enum DisplayCurrency: String, CaseIterable, Sendable {
    case usd
    case cny

    public var code: String { self == .usd ? "USD" : "CNY" }
    public var label: String { self == .usd ? "美元" : "人民币" }
}

/// Turns a provider amount into the user's chosen currency. Uses a fixed rate the user can edit,
/// so the panel never needs the network just to show a number.
public struct MoneyDisplay: Equatable, Sendable {
    public static let defaultRate = 7.1
    public static let usd = MoneyDisplay(currency: .usd, usdToCNY: defaultRate)

    public let currency: DisplayCurrency
    /// How many yuan one US dollar is worth.
    public let usdToCNY: Double

    public init(currency: DisplayCurrency, usdToCNY: Double) {
        self.currency = currency
        self.usdToCNY = usdToCNY > 0 ? usdToCNY : Self.defaultRate
    }

    /// Converts between USD and CNY; credits and other currencies are shown as they came.
    public func convert(_ amount: Double, from code: String) -> (amount: Double, code: String) {
        switch (code.uppercased(), currency) {
        case ("USD", .cny): return (amount * usdToCNY, "CNY")
        case ("CNY", .usd): return (amount / usdToCNY, "USD")
        default: return (amount, code)
        }
    }

    public func format(_ amount: Double, from code: String = "USD") -> String {
        let converted = convert(amount, from: code)
        return IslandFormat.money(converted.amount, currencyCode: converted.code)
    }
}
