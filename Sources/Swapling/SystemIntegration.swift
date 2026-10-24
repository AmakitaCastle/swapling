import AppKit
import Observation
import ServiceManagement

/// Calls `onChange` every time something `read` touches changes (Observation fires only once per
/// registration, so this re-registers after each change).
@MainActor
func observeChanges(_ read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
    withObservationTracking {
        read()
    } onChange: {
        Task { @MainActor in
            onChange()
            observeChanges(read, onChange: onChange)
        }
    }
}

/// Start Swapling when the user logs in, through the system's Login Items.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message when macOS refuses (e.g. when run outside an .app bundle).
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "没能修改登录项：\(error.localizedDescription)"
        }
    }
}

@MainActor
enum FullScreenDetector {
    /// Whether the frontmost app has a window covering the whole of `screen`, which is what a
    /// full-screen video, game or presentation looks like. Window bounds need no permission.
    static func frontmostAppIsFullScreen(on screen: NSScreen) -> Bool {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        let size = screen.frame.size
        return windows.contains { info in
            guard
                (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let raw = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: raw)
            else { return false }
            return abs(bounds.width - size.width) < 1 && abs(bounds.height - size.height) < 1
        }
    }
}
