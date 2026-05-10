import AppKit
import KeyboardShortcuts
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private static let didAutoRevealPopoverKey = "DidAutoRevealAppLauncherPopover"
    private static let menuBarSectionCollapsedKey = "MenuBarSectionCollapsed"

    private var statusItem: NSStatusItem!
    private var hideSectionItem: NSStatusItem!
    private let popover = NSPopover()
    private lazy var hostingController: NSHostingController<LauncherView> = {
        NSHostingController(rootView: LauncherView())
    }()

    private var rightClickEventMonitor: Any?
    private let visibleHideSectionLength: CGFloat = 14
    private var collapsedHideSectionLength: CGFloat = 2000
    private(set) var isMenuBarSectionCollapsed = false

    private let menuBarResourceUsageController = MenuBarResourceUsageController()

    private var dockPresentationObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        MenuBarResourceUsageDefaults.migrateFromDockPreferenceIfNeeded()
        UserDefaults.standard.register(defaults: [
            MenuBarResourceUsageDefaults.showInMenuBarKey: true,
            AppPresentationDefaults.showInDockAndAppSwitcherKey: false,
        ])
        applyActivationPolicyFromUserDefaults()
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        // Create before other items so this status entry sits toward the screen edge (with other extras).
        menuBarResourceUsageController.start()
        configureStatusItem()
        configureHideSectionItem()
        installRightClickMenuMonitor()
        updateCollapsedLengthForCurrentScreen()
        restoreSavedHideSectionState()

        KeyboardShortcuts.onKeyUp(for: .toggleLauncher) { [weak self] in
            self?.togglePopover()
        }

        dockPresentationObserver = NotificationCenter.default.addObserver(
            forName: .dockPresentationSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyActivationPolicyFromUserDefaults()
        }

        // First run: pop the popover once so it’s obvious where the app went.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.didAutoRevealPopoverKey) {
            defaults.set(true, forKey: Self.didAutoRevealPopoverKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown {
            showPopover()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let dockPresentationObserver {
            NotificationCenter.default.removeObserver(dockPresentationObserver)
        }
        if let rightClickEventMonitor {
            NSEvent.removeMonitor(rightClickEventMonitor)
        }
    }

    private func applyActivationPolicyFromUserDefaults() {
        let showDock = UserDefaults.standard.bool(forKey: AppPresentationDefaults.showInDockAndAppSwitcherKey)
        let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        updateCollapsedLengthForCurrentScreen()
    }

    // MARK: - Menu bar + popover

    private func configurePopover() {
        popover.contentSize = NSSize(width: 520, height: 460)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "applauncher_launcher"
        guard let button = statusItem.button else {
            return
        }
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "App Launcher")?
            .withSymbolConfiguration(symbolConfig)
        if let symbol {
            let img = symbol.copy() as? NSImage ?? symbol
            img.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            // SF Symbols unavailable (very rare): still show something tappable.
            button.image = nil
            button.title = "▦"
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        }
        button.toolTip = "App Launcher — click or press ⌥⇧Space"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp])
    }

    private func configureHideSectionItem() {
        hideSectionItem = NSStatusBar.system.statusItem(withLength: visibleHideSectionLength)
        hideSectionItem.autosaveName = "applauncher_hidden_section"
        guard let button = hideSectionItem.button else {
            return
        }

        let imageConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Hide menu bar section")?
            .withSymbolConfiguration(imageConfig)
        if let image {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.title = "|"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }

        button.toolTip = "Hide/show selected menu bar icons"
        button.target = self
        button.action = #selector(hideSectionItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func installRightClickMenuMonitor() {
        rightClickEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let button = self.statusItem.button else {
                return event
            }
            guard let eventWindow = event.window, eventWindow === button.window else {
                return event
            }
            let locationInButton = button.convert(event.locationInWindow, from: nil)
            guard button.bounds.contains(locationInButton) else {
                return event
            }
            self.showUtilityMenu(anchoredTo: button)
            return nil
        }
    }

    @objc private func statusItemClicked() {
        togglePopover()
    }

    @objc private func hideSectionItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showHideSectionMenu(anchoredTo: sender)
        } else {
            toggleMenuBarSectionCollapse()
        }
    }

    func togglePopover() {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else {
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .launcherDidShow, object: nil)
        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController?.view.window?.makeKey()
        }
    }

    func hidePopover() {
        popover.performClose(nil)
    }

    static func hidePopoverFromLauncher() {
        shared?.hidePopover()
    }

    static func toggleMenuBarSectionFromLauncher() {
        shared?.toggleMenuBarSectionCollapse()
    }

    static func currentMenuBarSectionCollapsedState() -> Bool {
        shared?.isMenuBarSectionCollapsed ?? UserDefaults.standard.bool(forKey: menuBarSectionCollapsedKey)
    }

    static func menuBarSectionPlacementIsValid() -> Bool {
        shared?.isHideSectionItemInValidPosition ?? false
    }

    /// Used by the local key monitor so arrow keys only apply while the popover is key.
    var isHandlingLauncherKeyboard: Bool {
        guard popover.isShown else {
            return false
        }
        guard let popWindow = popover.contentViewController?.view.window else {
            return false
        }
        return NSApp.keyWindow === popWindow
    }

    // MARK: - App menus

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About App Launcher", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Show Launcher", action: #selector(showLauncherFromMenu), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit App Launcher", action: #selector(quitApp), keyEquivalent: "q")

        for item in appMenu.items {
            item.target = self
        }

        NSApp.mainMenu = mainMenu
    }

    private func showUtilityMenu(anchoredTo button: NSStatusBarButton) {
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Launcher", action: #selector(showLauncherFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let toggleTitle = isMenuBarSectionCollapsed ? "Show hidden menu bar icons" : "Hide selected menu bar icons"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleMenuBarSectionFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let about = NSMenuItem(title: "About App Launcher", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit App Launcher", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func showHideSectionMenu(anchoredTo button: NSStatusBarButton) {
        let menu = NSMenu()

        let toggleTitle = isMenuBarSectionCollapsed ? "Show hidden section" : "Hide selected section"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleMenuBarSectionFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let guidance = NSMenuItem(title: "How to set this up", action: #selector(showHideSectionSetupGuidance), keyEquivalent: "")
        guidance.target = self
        menu.addItem(guidance)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func showLauncherFromMenu() {
        showPopover()
    }

    @objc private func toggleMenuBarSectionFromMenu() {
        toggleMenuBarSectionCollapse()
    }

    @objc private func showHideSectionSetupGuidance() {
        showHideSectionPositionAlert()
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "Copyright © 2026",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "App Launcher",
            .applicationVersion: "1.0.0",
            .credits: credits,
        ])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Hidden menu bar section

    var isHideSectionItemInValidPosition: Bool {
        guard
            let launcherX = statusItem.button?.window?.frame.origin.x,
            let separatorX = hideSectionItem.button?.window?.frame.origin.x
        else {
            return false
        }

        if NSApp.userInterfaceLayoutDirection == .leftToRight {
            return launcherX >= separatorX
        }
        return launcherX <= separatorX
    }

    private func restoreSavedHideSectionState() {
        let collapsed = UserDefaults.standard.bool(forKey: Self.menuBarSectionCollapsedKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else {
                return
            }
            if collapsed {
                self.collapseMenuBarSection(showGuidanceIfInvalid: false)
            } else {
                self.expandMenuBarSection()
            }
        }
    }

    private func updateCollapsedLengthForCurrentScreen() {
        let width = NSScreen.main?.visibleFrame.width ?? 1728
        collapsedHideSectionLength = max(500, min(width + 220, 4000))
        if isMenuBarSectionCollapsed {
            hideSectionItem.length = collapsedHideSectionLength
        }
    }

    private func toggleMenuBarSectionCollapse() {
        if isMenuBarSectionCollapsed {
            expandMenuBarSection()
        } else {
            collapseMenuBarSection(showGuidanceIfInvalid: true)
        }
    }

    private func collapseMenuBarSection(showGuidanceIfInvalid: Bool) {
        guard isHideSectionItemInValidPosition else {
            if showGuidanceIfInvalid {
                showHideSectionPositionAlert()
            }
            return
        }
        hideSectionItem.length = collapsedHideSectionLength
        setMenuBarSectionCollapsed(true)
    }

    private func expandMenuBarSection() {
        hideSectionItem.length = visibleHideSectionLength
        setMenuBarSectionCollapsed(false)
    }

    private func setMenuBarSectionCollapsed(_ collapsed: Bool) {
        isMenuBarSectionCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.menuBarSectionCollapsedKey)
        NotificationCenter.default.post(
            name: .menuBarSectionStateDidChange,
            object: nil,
            userInfo: ["collapsed": collapsed]
        )
    }

    private func showHideSectionPositionAlert() {
        let alert = NSAlert()
        alert.messageText = "Set up hidden icons first"
        alert.informativeText =
            "Hold Command and drag the small filter marker to the LEFT of the App Launcher icon. " +
            "Then drag menu bar icons you want hidden to the left of that marker, and keep your always-visible icons to the right."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }
}
