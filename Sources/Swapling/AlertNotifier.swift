import AppKit
import IslandCore
import UserNotifications

/// Optional sound and macOS notification that go with an island pop-up, for when the notch is
/// out of sight (full-screen video, another display).
@MainActor
enum AlertNotifier {
    /// Notification Center needs a real app bundle; `swift run` would crash without one.
    private static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func announce(_ group: AlertGroup, sound: Bool, notification: Bool) {
        if sound {
            NSSound(named: "Glass")?.play()
        }
        guard notification, canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = group.title
        content.body = group.subtitle(now: Date())
        let request = UNNotificationRequest(
            identifier: "swapling.\(group.providerID).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
