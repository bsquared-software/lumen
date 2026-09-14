import LumenCore
import SwiftUI

/// Rename displays, e.g. "Left OLED" instead of "Odyssey G81SF".
struct DisplaysSettingsView: View {
    @Environment(DisplayController.self) private var controller

    var body: some View {
        Form {
            ForEach(controller.displays) { detail in
                Section {
                    DisplayNameField(detail: detail)
                    LabeledContent("Model", value: detail.known.info.name)
                    LabeledContent("Status", value: status(of: detail))
                } header: {
                    Label(detail.known.displayName, systemImage: detail.known.info.isBuiltin ? "laptopcomputer" : "display")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func status(of detail: DisplayDetail) -> String {
        switch detail.known.status {
        case .online: detail.currentMode.map { "On · \(ModeCatalogue.summary($0))" } ?? "On"
        case .disconnected: "Switched off"
        case .unavailable: "Not plugged in"
        }
    }
}

private struct DisplayNameField: View {
    @Environment(DisplayController.self) private var controller
    let detail: DisplayDetail

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $name, prompt: Text(detail.known.info.name))
            .focused($isFocused)
            .onAppear { name = detail.known.customName ?? "" }
            .onSubmit(save)
            .onChange(of: isFocused) { _, focused in
                if !focused { save() }
            }
    }

    private func save() {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) != (detail.known.customName ?? "") else { return }
        Task { await controller.rename(detail.id, to: name) }
    }
}
