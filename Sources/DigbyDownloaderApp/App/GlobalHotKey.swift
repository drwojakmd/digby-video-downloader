import AppKit
import Carbon.HIToolbox

/// ⌃⌥⌘D anywhere: download the link on the clipboard. Uses the system hot-key service, which needs no
/// Accessibility or Input Monitoring permission (it only ever sees this one key combination).
enum GlobalHotKey {
    nonisolated(unsafe) private static var ref: EventHotKeyRef?
    nonisolated(unsafe) private static var handler: EventHandlerRef?
    nonisolated(unsafe) static var action: (() -> Void)?

    static func register(_ action: @escaping () -> Void) {
        guard ref == nil else { return }
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x4344_4C44), id: 1)   // "CDLD"
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
