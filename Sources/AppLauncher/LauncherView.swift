import AppKit
import SwiftUI

struct LauncherView: View {
    @StateObject private var viewModel = LauncherViewModel()
    @StateObject private var keyMonitor = LauncherKeyMonitor()

    @FocusState private var searchFocused: Bool

    @State private var showShortcutSettings = false
    @State private var menuBarSectionCollapsed = AppDelegate.currentMenuBarSectionCollapsedState()
    @AppStorage(DockResourceUsageDefaults.showOnDockIconKey) private var showDockResourceUsage = true

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
                        ForEach(viewModel.filtered) { app in
                            appRow(app)
                        }
                    } header: {
                        sectionHeader("Results")
                    }
                } else {
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
            Toggle(isOn: $showDockResourceUsage) {
                Label("CPU & RAM on Dock icon", systemImage: "chart.bar.fill")
            }
            .onChange(of: showDockResourceUsage) { _, _ in
                NotificationCenter.default.post(name: .dockResourceUsageSettingDidChange, object: nil)
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
        AppRow(app: app)
            .tag(app.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                viewModel.selection = app.id
                viewModel.openSelection()
            }
    }
}

private struct AppRow: View {
    let app: InstalledApp

    var body: some View {
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
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Press Return to launch")
    }

    private var accessibilityDescription: String {
        if let bid = app.bundleIdentifier {
            "\(app.name), \(bid)"
        } else {
            app.name
        }
    }
}
