import Combine
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query = ""
    @Published var selection: InstalledApp.ID?
    @Published private(set) var apps: [InstalledApp] = []

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filtered: [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// Order of rows as shown in the list (group order when browsing; alphabetical when searching).
    var orderedAppsForDisplay: [InstalledApp] {
        if isSearching {
            return filtered
        }
        return AppInstallGroup.displayOrder.flatMap { apps(in: $0) }
    }

    func apps(in group: AppInstallGroup) -> [InstalledApp] {
        apps.filter { $0.installGroup == group }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func load() {
        Task.detached(priority: .userInitiated) {
            let urls = AppScanner.scan()
            let unique = AppScanner.dedupe(urls: urls)
            let models = unique.map { InstalledApp(url: $0) }.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            await MainActor.run {
                self.apps = models
                self.syncSelectionWithDisplayOrder()
            }
        }
    }

    func resetSelectionForCurrentFilter() {
        if let sid = selection,
           orderedAppsForDisplay.contains(where: { $0.id == sid }) {
            return
        }
        selection = orderedAppsForDisplay.first?.id
    }

    private func syncSelectionWithDisplayOrder() {
        if selection == nil || orderedAppsForDisplay.first(where: { $0.id == selection }) == nil {
            selection = orderedAppsForDisplay.first?.id
        }
    }

    func moveSelection(_ delta: Int) {
        let list = orderedAppsForDisplay
        guard !list.isEmpty else {
            return
        }
        let ids = list.map(\.id)
        let current: Int
        if let sid = selection, let idx = ids.firstIndex(of: sid) {
            current = idx
        } else {
            current = 0
        }
        let next = min(max(current + delta, 0), list.count - 1)
        selection = ids[next]
    }

    func openSelection() {
        guard let id = selection ?? orderedAppsForDisplay.first?.id,
              let app = orderedAppsForDisplay.first(where: { $0.id == id })
        else {
            return
        }
        AppOpener.open(app)
        AppDelegate.hidePopoverFromLauncher()
    }
}
