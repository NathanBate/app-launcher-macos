import AppKit
import KeyboardShortcuts
import SwiftUI

// MARK: - Keyboard shortcut

struct ShortcutSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Click the field, then press the key combination you want. Conflicts with system shortcuts are blocked automatically."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    KeyboardShortcuts.Recorder("Open App Launcher:", name: .toggleLauncher)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Keyboard shortcut")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 240)
    }
}
