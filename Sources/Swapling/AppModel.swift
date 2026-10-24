import AppKit
import Foundation
import IslandCore
import Observation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "dev.swapling.app", category: "codexbar")
/// Opt-in: `defaults write dev.swapling.app hoverDebug -bool YES`, then
/// `log stream --predicate 'subsystem == "dev.swapling.app" && category == "hover"'`.
private let hoverLog = Logger(subsystem: "dev.swapling.app", category: "hover")

@Observable
@MainActor
final class AppModel {
    enum Surface: Equatable {
        case collapsed
        case expanded
        case alert(AlertGroup)

        var isCollapsed: Bool { self == .collapsed }
    }

    let prefs: Preferences
    var providers: [ProviderUsage] = []
    /// Full mark of each pay-as-you-go provider's bar (see `BalanceGauge`).
    private var balanceBaselines = UserDefaults.standard.dictionary(forKey: AppModel.balanceBaselinesKey) as? [String: Double] ?? [:]
    private static let balanceBaselinesKey = "balanceBaselines"
    var lastError: String?
    /// `lastError` sorted into a case with a next step.
    var lastIssue: DataIssue?
    /// Last refresh that read anything at all; per-provider age lives on each row.
    var lastRefresh: Date?
    var isRefreshing = false
    var isImportingCookies = false
    /// Why the last browser-login import failed, shown under the provider's card.
    var cookieImportMessage: String?
    var surface: Surface = .collapsed {
        didSet {
            // Each opening sorts once; while open, cards stay where they are.
            if surface == .expanded, oldValue != .expanded {
                snapshotPanelOrder()
                updateActiveAgent()
            }
        }
    }
    /// The AI the user is working with now (`ActiveAgent`), re-checked when the panel opens and
    /// when another app comes to the front; the panel's character follows it.
    private(set) var activeProviderID: String?
    /// The island window is actually visible (not hidden for full screen, not fully covered);
    /// animations beside the notch pause otherwise.
    var islandOnScreen = true
    @ObservationIgnored private lazy var activeAgentMonitor = ActiveAgentMonitor { [weak self] in
        self?.updateActiveAgent()
    }
    /// Card order frozen for the current opening of the panel.
    private(set) var panelOrderIDs: [String] = []
    /// Cards whose details (all windows, cost, source, diagnostics) are open.
    var expandedCardIDs: Set<String> = []
    /// Provider whose pop-up the user hovered, outlined in the expanded panel.
    var highlightedProviderID: String?
    /// The user pinned the expanded panel open with the header's pin button.
    var isPanelPinned = false
    /// The chosen expand shortcut is taken by another app.
    var shortcutRegistrationFailed = false
    /// Height of all provider cards as last laid out; kept across openings so the panel opens at
    /// its final size.
    var listContentHeight: CGFloat = 0

    /// Size of the black island as laid out, reported by the view for hit-testing.
    @ObservationIgnored var islandSize: CGSize = .zero
    @ObservationIgnored var openSettings: () -> Void = {}
    /// Settings tab shown the next time the window opens, and while it is open.
    var settingsTab: SettingsTab = .display
    /// Gives the island panel keyboard focus so Esc reaches it; set by the panel controller.
    @ObservationIgnored var focusPanel: () -> Void = {}

    @ObservationIgnored private var engine = AlertEngine()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var alertQueue: [AlertGroup] = []
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var resetRefreshes: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var isHovering = false
    @ObservationIgnored private var hoverIntent = HoverIntent(delay: HoverDelay.medium.seconds)
    @ObservationIgnored private var hoverOpenTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    static let alertDuration: Duration = .seconds(5)

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    var pinnedProviders: [ProviderUsage] {
        prefs.pinnedProviderIDs.compactMap { id in providers.first { $0.id == id } }
    }

    // MARK: Polling

    /// Client for the bundled CodexBar CLI, honoring the optional fallback path from Settings.
    var client: CodexBarClient {
        let path = prefs.cliPath.trimmingCharacters(in: .whitespaces)
        return CodexBarClient(customPath: path.isEmpty ? nil : path)
    }

    /// `--demo`: fixed scenario cards instead of CodexBar, with the panel open, for walkthroughs
    /// and screenshots. Reads and writes no provider data and raises no alerts.
    static let isDemo = CommandLine.arguments.contains("--demo")

    func start() {
        // Starts watching the frontmost app now, before Swapling itself can come to the front;
        // the notch marks the AI in use from the start.
        _ = activeAgentMonitor
        updateActiveAgent()
        if Self.isDemo {
            loadDemo()
            expandedCardIDs = ["claude:仅模型受限", "codex:重置时间未知"]
            isPanelPinned = true
            showPanel()
            let args = CommandLine.arguments
            if args.contains("--demo-characters"), !args.contains("--demo-scene") {
                pollTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(Self.demoScenePeriod))
                        self?.loadDemo()
                    }
                }
            }
            return
        }
        prepareConfig()
        // Numbers are hours old after a night with the lid shut; refresh once the network is back.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await self?.refresh()
            }
        }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = max(30, self.prefs.refreshInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Pulls the provider's login from the browser (may show one keychain prompt), then refreshes.
    func importBrowserLogin(provider id: String) async {
        guard !isImportingCookies else { return }
        isImportingCookies = true
        defer { isImportingCookies = false }
        do {
            cookieImportMessage = try await client.importBrowserCookies(provider: id)
        } catch {
            cookieImportMessage = error.localizedDescription
        }
        log.info("Browser login import for \(id, privacy: .public): \(self.cookieImportMessage == nil ? "ok" : "failed", privacy: .public)")
        await refresh()
    }

    /// `--demo-characters` steps through `DemoScenarios.characterScenes` every few seconds;
    /// `--demo-scene 3` holds one (1-based) for screenshots.
    private static func demoCharacterScene(now: Date) -> [ProviderUsage] {
        let scenes = DemoScenarios.characterScenes(now: now)
        let args = CommandLine.arguments
        let held = args.firstIndex(of: "--demo-scene").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
        let index = held.map { min(max($0 - 1, 0), scenes.count - 1) }
            ?? Int(now.timeIntervalSince1970 / demoScenePeriod) % scenes.count
        return scenes[index].providers
    }

    private static let demoScenePeriod: TimeInterval = 4

    private func loadDemo() {
        let now = Date()
        // `--demo-cards 正常,用完` keeps only cards whose id contains one of the words, so a
        // screenshot can show a few scenarios without scrolling.
        let args = CommandLine.arguments
        let words = args.firstIndex(of: "--demo-cards").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }?
            .split(separator: ",").map(String.init) ?? []
        let scenarios = args.contains("--demo-characters")
            ? Self.demoCharacterScene(now: now)
            : DemoScenarios.all(now: now).map(\.provider)
        providers = scenarios.filter { provider in
            words.isEmpty || words.contains { provider.id.contains($0) }
        }
        lastError = nil
        lastIssue = nil
        lastRefresh = now
        snapshotPanelOrder()
    }

    func refresh() async {
        // A CLI session going quiet only shows up over time; re-check with each poll.
        updateActiveAgent()
        if Self.isDemo { return loadDemo() }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let client = self.client
        do {
            let fetched = try await client.fetchAll()
            let now = Date()
            // A provider that failed this time keeps its last numbers, marked as carried over.
            providers = Freshness.merge(previous: providers, fetched: fetched, now: now)
            providers = BalanceGauge.apply(providers, baselines: &balanceBaselines)
            UserDefaults.standard.set(balanceBaselines, forKey: Self.balanceBaselinesKey)
            lastError = nil
            lastIssue = nil
            let failed = fetched.filter { $0.error != nil }.map(\.id)
            log.info("Fetched \(fetched.count) providers; errors: \(failed.joined(separator: ","), privacy: .public)")
            lastRefresh = now
            if panelOrderIDs.isEmpty || surface != .expanded { snapshotPanelOrder() }

            if !prefs.hasConfiguredPins, prefs.pinnedProviderIDs.isEmpty {
                prefs.pinnedProviderIDs = Array(fetched.filter { $0.error == nil }.prefix(2).map(\.id))
            }

            engine.thresholds = prefs.thresholds.alertLevels
            // Only current numbers may raise or clear alerts; old ones would announce stale news.
            let events = engine.process(providers.filter {
                Freshness.isCurrent($0, refreshInterval: prefs.refreshInterval, now: now)
            })
            if prefs.popupEnabled {
                enqueue(events)
            }
            scheduleResetRefreshes()
        } catch {
            let issue = DataIssue.classify(error)
            lastError = error.localizedDescription
            lastIssue = issue
            providers = Freshness.afterFailedRefresh(providers, issue: issue)
            log.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Seeds Swapling's own CodexBar config from the user's CodexBar config on first run.
    private func prepareConfig() {
        let client = self.client
        if let cli = client.resolvedCLI() {
            log.notice("CodexBar CLI (\(cli.source.rawValue, privacy: .public)): \(cli.path, privacy: .public)")
        } else {
            log.error("CodexBar CLI not found; bundled helper missing")
            remindManualDownload()
        }
        guard let configURL = client.configURL else { return }
        do {
            let seeds = CodexBarConfigLocation.codexBarConfigURLs(home: FileManager.default.homeDirectoryForCurrentUser)
            let result = try CodexBarConfigLocation.prepare(configURL: configURL, seedCandidates: seeds)
            log.notice("CodexBar config \(configURL.path, privacy: .public): \(String(describing: result), privacy: .public)")
        } catch {
            log.error("Could not seed CodexBar config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The bundled CLI was deleted: tell the user once per launch how to get it back by hand.
    private func remindManualDownload() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "缺少 CodexBar 命令行工具"
        alert.informativeText = CodexBarClientError.cliNotFound.localizedDescription
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(CodexBarCLILocator.manualDownloadURL)
        case .alertSecondButtonReturn:
            openSettings(for: .cliMissing)
        default: break
        }
    }

    /// Re-fetch shortly after an exhausted window's reset time so the "reset" pop-up is timely.
    private func scheduleResetRefreshes() {
        let now = Date()
        for provider in providers {
            for window in provider.windows where window.isExhausted {
                guard let resetsAt = window.resetsAt, resetsAt > now else { continue }
                let key = "\(provider.id)|\(window.id)|\(resetsAt.timeIntervalSince1970)"
                guard resetRefreshes[key] == nil else { continue }
                let delay = resetsAt.timeIntervalSince(now) + 10
                resetRefreshes[key] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
    }

    // MARK: Pop-up alerts

    private func enqueue(_ events: [IslandEvent]) {
        guard !events.isEmpty else { return }
        AlertGroup.enqueue(events, into: &alertQueue)
        if alertTask == nil { showNextAlert() }
    }

    /// Shows the next waiting pop-up. While the panel is open the queue waits; closing the panel
    /// picks it up again, so nothing that fired meanwhile is lost.
    private func showNextAlert() {
        guard !alertQueue.isEmpty, surface != .expanded, !isHovering else {
            alertTask = nil
            return
        }
        let group = alertQueue.removeFirst()
        AlertNotifier.announce(group, sound: prefs.alertSound, notification: prefs.systemNotification)
        withAnimation(IslandAnimation.pop) { surface = .alert(group) }
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: Self.alertDuration)
            guard let self, !Task.isCancelled else { return }
            if case .alert = self.surface {
                withAnimation(IslandAnimation.close) { self.surface = .collapsed }
                try? await Task.sleep(for: .milliseconds(450))
            }
            guard !Task.isCancelled else { return }
            self.showNextAlert()
        }
    }

    // MARK: Hover

    /// Hover input from the island view: `point` is in the hover view's coordinates (nil once the
    /// pointer leaves the view).
    func pointerMoved(to point: CGPoint?, inside: Bool) {
        if inside != isHovering, UserDefaults.standard.bool(forKey: "hoverDebug") {
            let where_ = point.map { "(\($0.x), \($0.y))" } ?? "left view"
            hoverLog.notice("""
            pointer \(where_, privacy: .public) inside=\(inside, privacy: .public) \
            surface=\(String(describing: self.surface), privacy: .public) \
            island=\(self.islandSize.width, privacy: .public)x\(self.islandSize.height, privacy: .public)
            """)
        }
        setHover(inside)
        // Opening waits for the pointer to rest (悬停延迟), so sweeping across doesn't open it.
        if inside, prefs.hoverToExpand, surface != .expanded {
            hoverIntent.delay = prefs.hoverDelay.seconds
            hoverIntent.update(point: point, at: Date())
            scheduleHoverOpen()
        } else if !inside {
            hoverIntent.update(point: nil, at: Date())
            hoverOpenTask?.cancel()
            hoverOpenTask = nil
        }
    }

    func setHover(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        collapseTask?.cancel()
        // Leaving closes a panel that isn't kept open, after the usual short grace period.
        if !inside, surface == .expanded, !isPanelPinned {
            scheduleCollapse()
        }
    }

    /// Waits until the pointer has rested on the island for the hover delay, then opens.
    private func scheduleHoverOpen() {
        guard hoverOpenTask == nil else { return }
        hoverOpenTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let now = Date()
                if self.hoverIntent.isReady(at: now) {
                    self.hoverOpenTask = nil
                    self.openFromHover()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func openFromHover() {
        guard isHovering, prefs.hoverToExpand, surface != .expanded else { return }
        // Hovering a pop-up opens the panel at that provider.
        if case let .alert(group) = surface {
            highlightedProviderID = group.providerID
        }
        alertTask?.cancel()
        alertTask = nil
        withAnimation(IslandAnimation.open) { surface = .expanded }
    }

    /// A click on the collapsed island or a pop-up: open the panel and keep it open (保持展开)
    /// until Esc, the close button, or turning 保持展开 off. A pop-up click highlights its provider.
    func openByClick() {
        if case let .alert(group) = surface {
            highlightedProviderID = group.providerID
        }
        isPanelPinned = true
        showPanel()
    }

    /// The expand shortcut: open and focus the panel, or close it when open.
    func togglePanelFromShortcut() {
        if surface == .expanded {
            collapsePanel()
        } else {
            showPanel()
        }
    }

    /// Pins the panel open (leaving the island no longer closes it), or releases it.
    func togglePanelPinned() {
        isPanelPinned.toggle()
        if !isPanelPinned, !isHovering, surface == .expanded {
            scheduleCollapse()
        }
    }

    /// Providers in panel order: sorted when the panel opened, then held still.
    var orderedProviders: [ProviderUsage] {
        PanelOrder.arrange(providers, snapshot: panelOrderIDs)
    }

    /// Sorts the panel now; on opening, and when the user picks another order.
    func snapshotPanelOrder() {
        let prefs = self.prefs
        let now = Date()
        panelOrderIDs = PanelOrder.ids(for: providers, mode: prefs.panelOrder) { provider in
            QuotaOverview.status(
                of: provider, thresholds: prefs.thresholds, refreshInterval: prefs.refreshInterval, now: now
            )
        }
    }

    /// `--demo-active claude` stands in for detection in demos and screenshots.
    func updateActiveAgent() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--demo-active"), args.indices.contains(index + 1) {
            activeProviderID = args[index + 1]
            return
        }
        guard prefs.mascotFollowsActiveAgent else {
            activeProviderID = nil
            return
        }
        activeProviderID = activeAgentMonitor.detect()
        log.debug("Active agent: \(self.activeProviderID ?? "none", privacy: .public) (front: \(self.activeAgentMonitor.lastFrontmostBundleID ?? "none", privacy: .public))")
    }

    func toggleCardDetails(_ id: String) {
        if expandedCardIDs.contains(id) {
            expandedCardIDs.remove(id)
        } else {
            expandedCardIDs.insert(id)
        }
    }

    /// Opens Settings on the page where `issue` gets fixed.
    func openSettings(for issue: DataIssue) {
        settingsTab = SettingsTab(issue.settingsPage)
        openSettings()
    }

    /// Opens the panel without hovering (menu-bar item), focused so Esc closes it again.
    func showPanel() {
        collapseTask?.cancel()
        alertTask?.cancel()
        alertTask = nil
        if surface != .expanded {
            withAnimation(IslandAnimation.open) { surface = .expanded }
        }
        focusPanel()
    }

    /// Closes the panel right away (Esc, or focus moved elsewhere), releasing a pin.
    func collapsePanel() {
        guard surface == .expanded else { return }
        isPanelPinned = false
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            await self?.collapseAndCatchUp()
        }
    }

    /// The panel lost keyboard focus: close it unless the pointer is on it or it is pinned.
    func panelResignedFocus() {
        guard surface == .expanded, !isHovering, !isPanelPinned else { return }
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, !self.isHovering, !self.isPanelPinned else { return }
            await self.collapseAndCatchUp()
        }
    }

    private func collapseAndCatchUp() async {
        withAnimation(IslandAnimation.close) { surface = .collapsed }
        highlightedProviderID = nil
        // Pop-ups that came in while the panel was open show now.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, !isHovering, alertTask == nil else { return }
        showNextAlert()
    }
}

enum IslandAnimation {
    /// System Settings → Accessibility → Display → Reduce motion.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // Spring values follow CodeIsland's NotchAnimation (MIT): slight bounce on open, none on close.
    // With Reduce Motion: a short fade-like ease with no bounce.
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82)
    }
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 1.0)
    }
    static var pop: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.65)
    }
}

enum SettingsTab: Hashable {
    case display
    case providers
    case system

    init(_ page: DataIssue.SettingsPage) {
        switch page {
        case .display: self = .display
        case .providers: self = .providers
        }
    }
}
