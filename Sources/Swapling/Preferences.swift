import Foundation
import IslandCore
import Observation

/// User settings, persisted in UserDefaults.
@Observable
@MainActor
final class Preferences {
    private enum Key {
        static let pinned = "pinnedProviderIDs"
        static let configuredPins = "hasConfiguredPins"
        static let refreshInterval = "refreshInterval"
        static let warnLevel1 = "warnLevel1"
        static let warnLevel2 = "warnLevel2"
        static let popupEnabled = "popupEnabled"
        static let cliPath = "cliPath"
        static let showRemaining = "showRemaining"
        static let showWindowLabel = "showWindowLabel"
        static let compactEars = "compactEars"
        static let earItemLimit = "earItemLimit"
        static let alertSound = "alertSound"
        static let systemNotification = "systemNotification"
        static let screenChoice = "screenChoice"
        static let hideInFullScreen = "hideInFullScreen"
        static let hideFromScreenSharing = "hideFromScreenSharing"
        static let menuBarPercent = "menuBarPercent"
        static let panelOrder = "panelOrder"
        static let hoverToExpand = "hoverToExpand"
        static let hoverDelay = "hoverDelay"
        static let expandShortcut = "expandShortcut"
        static let displayCurrency = "displayCurrency"
        static let usdToCNY = "usdToCNY"
        static let mascotFollowsActiveAgent = "mascotFollowsActiveAgent"
    }

    static let maxPinned = 4

    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Providers shown beside the notch, in order. Every enabled provider
    /// still appears in the expanded panel.
    var pinnedProviderIDs: [String] {
        didSet { defaults.set(pinnedProviderIDs, forKey: Key.pinned) }
    }

    /// False until the user picks pins themselves; before that the first two providers are pinned.
    var hasConfiguredPins: Bool {
        didSet { defaults.set(hasConfiguredPins, forKey: Key.configuredPins) }
    }

    var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    var warnLevel1: Int {
        didSet { defaults.set(warnLevel1, forKey: Key.warnLevel1) }
    }

    var warnLevel2: Int {
        didSet { defaults.set(warnLevel2, forKey: Key.warnLevel2) }
    }

    /// Colours, the glow and pop-up alerts all read this one pair of lines.
    var thresholds: QuotaThresholds {
        QuotaThresholds(warn1: warnLevel1, warn2: warnLevel2)
    }

    var popupEnabled: Bool {
        didSet { defaults.set(popupEnabled, forKey: Key.popupEnabled) }
    }

    /// Collapsed island shows what's left (like a battery) instead of what's used.
    var showRemaining: Bool {
        didSet { defaults.set(showRemaining, forKey: Key.showRemaining) }
    }

    /// Tag the collapsed percent with its quota window ("5h", "周").
    var showWindowLabel: Bool {
        didSet { defaults.set(showWindowLabel, forKey: Key.showWindowLabel) }
    }

    /// Icon and ring only beside the notch, no numbers.
    var compactEars: Bool {
        didSet { defaults.set(compactEars, forKey: Key.compactEars) }
    }

    /// How many pinned providers are drawn beside the notch at once; extra ones rotate in.
    var earItemLimit: Int {
        didSet { defaults.set(earItemLimit, forKey: Key.earItemLimit) }
    }

    /// Play a short sound with each pop-up.
    var alertSound: Bool {
        didSet { defaults.set(alertSound, forKey: Key.alertSound) }
    }

    /// Also post each pop-up to Notification Center.
    var systemNotification: Bool {
        didSet { defaults.set(systemNotification, forKey: Key.systemNotification) }
    }

    /// Which display the island lives on: `auto` (the one with a notch), `main` (the menu-bar
    /// display), or a display's name.
    var screenChoice: String {
        didSet { defaults.set(screenChoice, forKey: Key.screenChoice) }
    }

    /// Get out of the way while a full-screen app is in front.
    var hideInFullScreen: Bool {
        didSet { defaults.set(hideInFullScreen, forKey: Key.hideInFullScreen) }
    }

    /// Keep the island out of screen sharing and recordings.
    var hideFromScreenSharing: Bool {
        didSet { defaults.set(hideFromScreenSharing, forKey: Key.hideFromScreenSharing) }
    }

    /// Show the most-used provider's percent next to the menu-bar icon.
    var menuBarPercent: Bool {
        didSet { defaults.set(menuBarPercent, forKey: Key.menuBarPercent) }
    }

    /// Panel card order: CodexBar's fixed order, or what needs attention first.
    var panelOrder: PanelOrderMode {
        didSet { defaults.set(panelOrder.rawValue, forKey: Key.panelOrder) }
    }

    /// Hovering the island opens the panel. Off: only a click (or the shortcut) opens it.
    var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: Key.hoverToExpand) }
    }

    /// How long the pointer rests on the island before the panel opens.
    var hoverDelay: HoverDelay {
        didSet { defaults.set(hoverDelay.rawValue, forKey: Key.hoverDelay) }
    }

    /// System-wide shortcut that opens or closes the panel.
    var expandShortcut: ExpandShortcut {
        didSet { defaults.set(expandShortcut.rawValue, forKey: Key.expandShortcut) }
    }

    /// Currency for balances and estimated spend in the panel.
    var displayCurrency: DisplayCurrency {
        didSet { defaults.set(displayCurrency.rawValue, forKey: Key.displayCurrency) }
    }

    /// Fixed USD → CNY rate used when showing amounts in yuan.
    var usdToCNY: Double {
        didSet { defaults.set(usdToCNY, forKey: Key.usdToCNY) }
    }

    var money: MoneyDisplay {
        MoneyDisplay(currency: displayCurrency, usdToCNY: usdToCNY)
    }

    /// The panel's character shows the AI in use right now (frontmost app or recent CLI session).
    var mascotFollowsActiveAgent: Bool {
        didSet { defaults.set(mascotFollowsActiveAgent, forKey: Key.mascotFollowsActiveAgent) }
    }

    /// Fallback CodexBar CLI location, used only when the bundled helper is missing (e.g. `swift run`).
    var cliPath: String {
        didSet { defaults.set(cliPath, forKey: Key.cliPath) }
    }

    init() {
        defaults.register(defaults: [
            Key.refreshInterval: 120.0,
            Key.warnLevel1: 80,
            Key.warnLevel2: 95,
            Key.popupEnabled: true,
            Key.showWindowLabel: true,
            Key.earItemLimit: 2,
            Key.screenChoice: "auto",
            Key.hoverToExpand: true,
            Key.usdToCNY: MoneyDisplay.defaultRate,
            Key.mascotFollowsActiveAgent: true,
        ])
        pinnedProviderIDs = defaults.stringArray(forKey: Key.pinned) ?? []
        hasConfiguredPins = defaults.bool(forKey: Key.configuredPins)
        refreshInterval = defaults.double(forKey: Key.refreshInterval)
        // Older builds could save the first line at or above the second; read it back repaired.
        let stored = QuotaThresholds(
            warn1: defaults.integer(forKey: Key.warnLevel1), warn2: defaults.integer(forKey: Key.warnLevel2)
        )
        warnLevel1 = stored.warn1
        warnLevel2 = stored.warn2
        popupEnabled = defaults.bool(forKey: Key.popupEnabled)
        cliPath = defaults.string(forKey: Key.cliPath) ?? ""
        showRemaining = defaults.bool(forKey: Key.showRemaining)
        showWindowLabel = defaults.bool(forKey: Key.showWindowLabel)
        compactEars = defaults.bool(forKey: Key.compactEars)
        earItemLimit = defaults.integer(forKey: Key.earItemLimit)
        alertSound = defaults.bool(forKey: Key.alertSound)
        systemNotification = defaults.bool(forKey: Key.systemNotification)
        screenChoice = defaults.string(forKey: Key.screenChoice) ?? "auto"
        hideInFullScreen = defaults.bool(forKey: Key.hideInFullScreen)
        hideFromScreenSharing = defaults.bool(forKey: Key.hideFromScreenSharing)
        menuBarPercent = defaults.bool(forKey: Key.menuBarPercent)
        hoverToExpand = defaults.bool(forKey: Key.hoverToExpand)
        hoverDelay = defaults.string(forKey: Key.hoverDelay).flatMap(HoverDelay.init(rawValue:)) ?? .medium
        expandShortcut = defaults.string(forKey: Key.expandShortcut).flatMap(ExpandShortcut.init(rawValue:)) ?? .off
        displayCurrency = defaults.string(forKey: Key.displayCurrency).flatMap(DisplayCurrency.init(rawValue:)) ?? .usd
        usdToCNY = defaults.double(forKey: Key.usdToCNY)
        mascotFollowsActiveAgent = defaults.bool(forKey: Key.mascotFollowsActiveAgent)
        panelOrder = defaults.string(forKey: Key.panelOrder).flatMap(PanelOrderMode.init(rawValue:)) ?? .attention
    }

    func isPinned(_ id: String) -> Bool {
        pinnedProviderIDs.contains(id)
    }

    /// Moves a pinned provider one place left (-1) or right (+1) beside the notch.
    func movePinned(_ id: String, by offset: Int) {
        guard let index = pinnedProviderIDs.firstIndex(of: id) else { return }
        let target = index + offset
        guard pinnedProviderIDs.indices.contains(target) else { return }
        hasConfiguredPins = true
        pinnedProviderIDs.swapAt(index, target)
    }

    func setPinned(_ id: String, _ pinned: Bool) {
        hasConfiguredPins = true
        if pinned {
            guard !isPinned(id), pinnedProviderIDs.count < Self.maxPinned else { return }
            pinnedProviderIDs.append(id)
        } else {
            pinnedProviderIDs.removeAll { $0 == id }
        }
    }
}
