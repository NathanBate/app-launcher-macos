import AppKit
import Foundation

/// Opens System Settings panes where Apple lets users control menu bar / Control Center modules.
enum SystemSettingsDeepLink {
    /// Control Center: which modules appear in the menu bar.
    static func openControlCenter() {
        open("x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
    }

    /// Desktop: menu bar auto-hide, stage manager adjacent options (varies by macOS version).
    static func openDesktop() {
        open("x-apple.systempreferences:com.apple.Desktop-Settings.extension")
    }

    /// Focus / Do Not Disturb (often affects menu bar indicators).
    static func openFocus() {
        open("x-apple.systempreferences:com.apple.Focus-Settings.extension")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
