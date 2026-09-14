import Carbon.HIToolbox
import LumenCore

/// Global shortcuts through Carbon's `RegisterEventHotKey`. It needs no Accessibility
/// permission and no third-party dependency.
@MainActor
final class HotkeyCenter {
    private var registered: [EventHotKeyRef] = []
    private var presetsByHotkeyID: [UInt32: Preset.ID] = [:]
    private var onTrigger: ((Preset.ID) -> Void)?
    private var handler: EventHandlerRef?

    /// Replaces every registration. Returns a message for each preset whose shortcut could not
    /// be registered.
    func register(_ entries: [(Preset.ID, Hotkey)], onTrigger: @escaping (Preset.ID) -> Void) -> [Preset.ID: String] {
        unregisterAll()
        installHandlerIfNeeded()
        self.onTrigger = onTrigger

        var problems: [Preset.ID: String] = [:]
        var taken = Set<String>()
        for (index, (presetID, hotkey)) in entries.enumerated() {
            guard taken.insert("\(hotkey.keyCode)-\(hotkey.modifiers)").inserted else {
                problems[presetID] = "Another preset already uses \(hotkey.displayString)."
                continue
            }
            let hotkeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotkeyID, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registered.append(reference)
                presetsByHotkeyID[hotkeyID.id] = presetID
            } else {
                problems[presetID] = "\(hotkey.displayString) is already in use, so it won’t work."
            }
        }
        return problems
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        presetsByHotkeyID = [:]
    }

    fileprivate func trigger(_ hotkeyID: UInt32) {
        guard let presetID = presetsByHotkeyID[hotkeyID] else { return }
        onTrigger?(presetID)
    }

    /// 'LUMN'
    private static let signature: OSType = 0x4C55_4D4E

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { center.trigger(hotkeyID.id) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
