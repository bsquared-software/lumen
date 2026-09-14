import AppKit
import LumenCore
import SwiftUI

/// Click, then press a shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var hotkey: Hotkey?
    var onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Type shortcut…" : hotkey?.displayString ?? "Record Shortcut")
                    .frame(minWidth: 110)
            }
            if hotkey != nil, !isRecording {
                Button("Clear Shortcut", systemImage: "xmark.circle.fill") { hotkey = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let hasModifiers = !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        switch event.keyCode {
        case 53:
            stop()
        case 51 where !hasModifiers, 117 where !hasModifiers:
            hotkey = nil
            stop()
        default:
            let modifiers = HotkeyFormatting.carbonModifiers(fromCocoa: event.modifierFlags.rawValue)
            guard HotkeyFormatting.isAcceptable(modifiers: modifiers) else {
                NSSound.beep()
                return
            }
            let keyCode = UInt32(event.keyCode)
            hotkey = Hotkey(
                keyCode: keyCode, modifiers: modifiers,
                keyLabel: HotkeyFormatting.keyLabel(keyCode: keyCode, characters: event.charactersIgnoringModifiers)
            )
            stop()
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }
}
