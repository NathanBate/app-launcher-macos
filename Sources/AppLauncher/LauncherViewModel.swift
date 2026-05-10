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

    /// Search matches; use ``searchResultsOrdered`` for display order (favorites first).
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

    /// Favorites that still exist, in saved order (for the top section when browsing).
    var favoritesForDisplay: [InstalledApp] {
        AppFavorites.shared.orderedIds.compactMap { id in apps.first(where: { $0.id == id }) }
    }

    /// When searching: favorites matching the query first (saved order), then the rest alphabetically.
    var searchResultsOrdered: [InstalledApp] {
        let matches = filtered
        let favPart = AppFavorites.shared.orderedIds.compactMap { id in matches.first(where: { $0.id == id }) }
        let rest = matches
            .filter { !AppFavorites.shared.contains($0.id) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        return favPart + rest
    }

    /// Order of rows as shown in the list (favorites + groups when browsing; favorites first when searching).
    var orderedAppsForDisplay: [InstalledApp] {
        if isSearching {
            return searchResultsOrdered
        }
        return favoritesForDisplay + AppInstallGroup.displayOrder.flatMap { apps(in: $0) }
    }

    func apps(in group: AppInstallGroup) -> [InstalledApp] {
        apps
            .filter { $0.installGroup == group && !AppFavorites.shared.contains($0.id) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func toggleFavorite(id: InstalledApp.ID) {
        AppFavorites.shared.toggle(id)
        syncSelectionWithDisplayOrder()
        objectWillChange.send()
    }

    func isFavorite(id: InstalledApp.ID) -> Bool {
        AppFavorites.shared.contains(id)
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
                AppFavorites.shared.prune(toInstalledIds: Set(models.map(\.id)))
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
