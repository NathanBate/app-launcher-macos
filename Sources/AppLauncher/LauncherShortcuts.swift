import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLauncher = Self(
        "toggleLauncher",
        default: KeyboardShortcuts.Shortcut(.space, modifiers: [.option, .shift])
    )
}
