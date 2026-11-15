import Carbon.HIToolbox

/// System-wide hotkey via Carbon's RegisterEventHotKey (works without Accessibility permission).
@MainActor
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    /// Returns nil if the combination is already taken by another app.
    init?(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x444C_4142), id: id)  // 'DLAB'
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                  GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        Self.actions[id] = action
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            MainActor.assumeIsolated { HotKey.actions[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
