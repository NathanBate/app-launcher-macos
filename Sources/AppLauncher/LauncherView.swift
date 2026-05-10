import AppKit
import SwiftUI

struct LauncherView: View {
    @StateObject private var viewModel = LauncherViewModel()
    @StateObject private var keyMonitor = LauncherKeyMonitor()

    @FocusState private var searchFocused: Bool

    @State private var showShortcutSettings = false
    @State private var menuBarSectionCollapsed = AppDelegate.currentMenuBarSectionCollapsedState()
    @AppStorage(MenuBarResourceUsageDefaults.showInMenuBarKey) private var showMenuBarResourceUsage = true
    @AppStorage(AppPresentationDefaults.showInDockAndAppSwitcherKey) private var showAppInDockAndAppSwitcher = false

    @State private var launchAtLogin = LaunchAtLogin.isRegisteredOrPending

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                TextField("Search applications", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .focused($searchFocused)
                    .frame(maxWidth: .infinity)
                    .onChange(of: viewModel.query) { _, _ in
                        viewModel.resetSelectionForCurrentFilter()
                    }
                    .onSubmit {
                        viewModel.openSelection()
                    }

                settingsMenu
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: $viewModel.selection) {
                if viewModel.isSearching {
                    Section {
                        ForEach(viewModel.searchResultsOrdered) { app in
                            appRow(app)
                        }
                    } header: {
                        sectionHeader("Results")
                    }
                } else {
                    if !viewModel.favoritesForDisplay.isEmpty {
                        Section {
                            ForEach(viewModel.favoritesForDisplay) { app in
                                appRow(app)
                            }
                        } header: {
                            sectionHeader("Favorites")
                        }
                    }
                    ForEach(AppInstallGroup.displayOrder) { group in
                        let groupApps = viewModel.apps(in: group)
                        if !groupApps.isEmpty {
                            Section {
                                ForEach(groupApps) { app in
                                    appRow(app)
                                }
                            } header: {
                                sectionHeader(group.title)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 500, minHeight: 380)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thickMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(10)
        .focusable()
        .onKeyPress(.return) {
            viewModel.openSelection()
            return .handled
        }
        .onExitCommand {
            AppDelegate.hidePopoverFromLauncher()
        }
        .onAppear {
            let vm = viewModel
            vm.load()
            searchFocused = true
            vm.resetSelectionForCurrentFilter()
            menuBarSectionCollapsed = AppDelegate.currentMenuBarSectionCollapsedState()

            keyMonitor.onKeyDown = { event in
                guard AppDelegate.shared?.isHandlingLauncherKeyboard == true else {
                    return event
                }
                switch event.keyCode {
                case 125:
                    vm.moveSelection(1)
                    return nil
                case 126:
                    vm.moveSelection(-1)
                    return nil
                default:
                    return event
                }
            }
            keyMonitor.start()
        }
        .onDisappear {
            keyMonitor.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidShow)) { _ in
            searchFocused = true
            viewModel.resetSelectionForCurrentFilter()
            launchAtLogin = LaunchAtLogin.isRegisteredOrPending
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSectionStateDidChange)) { _ in
            menuBarSectionCollapsed = AppDelegate.currentMenuBarSectionCollapsedState()
        }
        .sheet(isPresented: $showShortcutSettings) {
            ShortcutSettingsSheet()
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                AppDelegate.toggleMenuBarSectionFromLauncher()
                menuBarSectionCollapsed = AppDelegate.currentMenuBarSectionCollapsedState()
            } label: {
                Label(
                    menuBarSectionCollapsed ? "Show hidden menu bar icons" : "Hide selected menu bar icons",
                    systemImage: menuBarSectionCollapsed ? "eye" : "eye.slash"
                )
            }
            Button {
                showShortcutSettings = true
            } label: {
                Label("Keyboard shortcut…", systemImage: "keyboard")
            }
            Toggle(isOn: $showMenuBarResourceUsage) {
                Label("CPU & RAM in menu bar", systemImage: "chart.bar.fill")
            }
            .onChange(of: showMenuBarResourceUsage) { _, _ in
                NotificationCenter.default.post(name: .menuBarResourceUsageSettingDidChange, object: nil)
            }
            Toggle(isOn: $showAppInDockAndAppSwitcher) {
                Label("Dock & App Switcher icon", systemImage: "dock.rectangle")
            }
            .onChange(of: showAppInDockAndAppSwitcher) { _, _ in
                NotificationCenter.default.post(name: .dockPresentationSettingDidChange, object: nil)
            }
            Toggle(isOn: launchAtLoginBinding) {
                Label("Open at login", systemImage: "clock.arrow.circlepath")
            }
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit App Launcher", systemImage: "power")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                let previous = launchAtLogin
                launchAtLogin = newValue
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isRegisteredOrPending
                } catch {
                    launchAtLogin = previous
                }
            }
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        AppRow(
            app: app,
            isFavorite: viewModel.isFavorite(id: app.id),
            onToggleFavorite: { viewModel.toggleFavorite(id: app.id) },
            onLaunch: {
                viewModel.selection = app.id
                viewModel.openSelection()
            }
        )
        .tag(app.id)
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onLaunch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body)
                    if let bid = app.bundleIdentifier {
                        Text(bid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onLaunch()
            }

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Click to launch")
    }

    private var accessibilityDescription: String {
        if let bid = app.bundleIdentifier {
            "\(app.name), \(bid)"
        } else {
            app.name
        }
    }
}
