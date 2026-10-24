import AppKit
import SwiftUI

/// Notch measurements of the screen the island lives on.
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    /// Height of the transparent panel the island draws in; caps the expanded panel's list.
    var panelHeight: CGFloat = 640

    init(hasNotch: Bool, notchWidth: CGFloat, notchHeight: CGFloat) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    @MainActor
    init(screen: NSScreen) {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        if left > 0 || right > 0 {
            hasNotch = true
            notchWidth = screen.frame.width - left - right
            notchHeight = max(screen.safeAreaInsets.top, 24)
        } else {
            // No notch: draw a pill of similar size under the menu bar centre.
            hasNotch = false
            notchWidth = 180
            notchHeight = menuBar > 5 ? menuBar : 25
        }
    }

    /// `choice` is Preferences.screenChoice: `auto` prefers the notched display, `main` the
    /// menu-bar display, anything else a display's name (falling back to `auto` when unplugged).
    @MainActor
    static func preferredScreen(choice: String = "auto") -> NSScreen {
        let menuBarScreen = NSScreen.screens.first ?? NSScreen.main!
        switch choice {
        case "main":
            return menuBarScreen
        case "auto":
            break
        default:
            if let named = NSScreen.screens.first(where: { $0.localizedName == choice }) { return named }
        }
        return NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? menuBarScreen
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // The island overlaps the menu bar on purpose; don't let AppKit push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// First click on a non-activating panel should hit the button, not just focus the window.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandPanelController {
    static let panelWidth: CGFloat = 680
    static let minPanelHeight: CGFloat = 640

    /// Tall enough for long provider lists on big screens, never past most of the screen.
    static func panelSize(for screen: NSScreen) -> NSSize {
        let height = min(max(minPanelHeight, screen.visibleFrame.height * 0.8), 1100)
        return NSSize(width: panelWidth, height: height)
    }

    private let model: AppModel
    private var panel: NSPanel?
    private var screen: NSScreen
    private var observers: [NSObjectProtocol] = []
    private var escMonitor: Any?

    init(model: AppModel) {
        self.model = model
        self.screen = NotchGeometry.preferredScreen(choice: model.prefs.screenChoice)
        // The panel's pixel font, before the first view draws.
        PixelFont.register()
    }

    func show() {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize(for: screen)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.panel = panel

        rebuild()
        panel.orderFrontRegardless()

        model.focusPanel = { [weak panel] in
            panel?.orderFrontRegardless()
            panel?.makeKey()
        }
        // Esc closes the open panel whenever the panel has keyboard focus (opened from the menu
        // bar, or after a click inside it). Hovering alone doesn't take focus from the user's app.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, event.keyCode == 53, event.window === panel, self.model.surface == .expanded else {
                return event
            }
            self.model.collapsePanel()
            return nil
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                self?.model.islandOnScreen = panel?.occlusionState.contains(.visible) ?? false
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.panelResignedFocus() }
        })

        let prefs = model.prefs
        observeChanges({ _ = prefs.screenChoice }) { [weak self] in self?.rebuild() }
        observeChanges({ _ = (prefs.hideInFullScreen, prefs.hideFromScreenSharing) }) { [weak self] in
            self?.applyVisibility()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Entering full screen animates; check once it has settled.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(700))
                    self?.applyVisibility()
                }
            })
        }
        applyVisibility()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
    }

    private func rebuild() {
        guard let panel else { return }
        screen = NotchGeometry.preferredScreen(choice: model.prefs.screenChoice)
        let size = Self.panelSize(for: screen)
        var geometry = NotchGeometry(screen: screen)
        geometry.panelHeight = size.height
        let root = IslandRootView(model: model, geometry: geometry)
        let host = IslandHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        applyVisibility()
    }

    /// Hides the island behind full-screen apps and from screen sharing when the user asked to.
    private func applyVisibility() {
        guard let panel else { return }
        let prefs = model.prefs
        panel.sharingType = prefs.hideFromScreenSharing ? .none : .readOnly
        let hide = prefs.hideInFullScreen && FullScreenDetector.frontmostAppIsFullScreen(on: screen)
        if hide, panel.isVisible {
            panel.orderOut(nil)
        } else if !hide, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
