import AppKit
import IslandCore

@main
enum SwaplingMain {
    @MainActor
    static func main() {
        // Writing an API key to a CLI that already exited must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar style app: no Dock icon, no main window.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panelController: IslandPanelController!
    private var settingsController: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences()
        model = AppModel(prefs: prefs)
        settingsController = SettingsWindowController(model: model)
        model.openSettings = { [weak self] in self?.settingsController.show() }

        panelController = IslandPanelController(model: model)
        panelController.show()
        setupStatusItem()
        setupHotKey()
        model.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = BrandIcon.menuBarImage
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "显示额度面板", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Swapling", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu

        observeChanges({ [weak self] in
            guard let self else { return }
            _ = (self.model.providers, self.model.prefs.menuBarPercent, self.model.prefs.showRemaining)
        }) { [weak self] in
            self?.updateStatusTitle()
        }
        updateStatusTitle()
    }

    /// The expand shortcut from Settings, re-registered whenever it changes.
    private func setupHotKey() {
        let hotKey = GlobalHotKey { [weak self] in self?.model.togglePanelFromShortcut() }
        self.hotKey = hotKey
        observeChanges({ [weak self] in _ = self?.model.prefs.expandShortcut }) { [weak self] in
            guard let self else { return }
            self.model.shortcutRegistrationFailed = !hotKey.register(self.model.prefs.expandShortcut)
        }
        model.shortcutRegistrationFailed = !hotKey.register(model.prefs.expandShortcut)
    }

    /// A fallback view of the island when the notch is hidden or on another display: the most-used
    /// provider's percent beside the menu-bar icon.
    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let prefs = model.prefs
        // Only current numbers; with none, a dash rather than a percent that looks normal.
        let window = model.providers
            .filter { Freshness.isCurrent($0, refreshInterval: prefs.refreshInterval, now: Date()) }
            .compactMap(\.tightestWindow)
            .max { $0.usedPercent < $1.usedPercent }
        if prefs.menuBarPercent {
            button.title = " " + (window.map {
                IslandFormat.percent(CollapsedDisplay.shownPercent(for: $0, showRemaining: prefs.showRemaining))
            } ?? "–")
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// Opens the panel without hovering the notch; Esc or clicking elsewhere closes it.
    @objc private func showPanel() {
        model.showPanel()
    }

    @objc private func refreshNow() {
        Task { await model.refresh() }
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
