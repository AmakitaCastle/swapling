import Carbon.HIToolbox
import Foundation

/// Shortcut choices for opening the panel. A short fixed list keeps clear of common app shortcuts
/// and needs no key recorder.
enum ExpandShortcut: String, CaseIterable, Identifiable {
    case off
    case controlOptionI
    case controlOptionSpace
    case controlOptionQ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "不使用"
        case .controlOptionI: return "⌃⌥I"
        case .controlOptionSpace: return "⌃⌥Space"
        case .controlOptionQ: return "⌃⌥Q"
        }
    }

    fileprivate var keyCode: UInt32? {
        switch self {
        case .off: return nil
        case .controlOptionI: return UInt32(kVK_ANSI_I)
        case .controlOptionSpace: return UInt32(kVK_Space)
        case .controlOptionQ: return UInt32(kVK_ANSI_Q)
        }
    }
}

/// A system-wide shortcut through Carbon's RegisterEventHotKey, which (unlike a global key
/// monitor) needs no Accessibility permission and only sees its own key combination.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, context, &handler)
    }

    /// Registers `shortcut`, replacing the previous one. Returns false when the system refused it
    /// (usually because another app already owns that combination).
    @discardableResult
    func register(_ shortcut: ExpandShortcut) -> Bool {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let keyCode = shortcut.keyCode else { return true }
        let id = EventHotKeyID(signature: OSType(0x4349_534C), id: 1) // "CISL"
        let status = RegisterEventHotKey(
            keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref
        )
        return status == noErr
    }
}
