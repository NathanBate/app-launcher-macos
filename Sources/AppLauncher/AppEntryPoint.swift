import AppKit

@main
enum AppLauncherEntryPoint {
    /// Retained for the lifetime of the process (`NSApplication.delegate` is weak).
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
