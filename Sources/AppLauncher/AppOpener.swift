import AppKit
import Foundation

enum AppOpener {
    static func open(_ app: InstalledApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                NSLog("AppLauncher: failed to open \(app.url.path): \(error.localizedDescription)")
            }
        }
    }
}
