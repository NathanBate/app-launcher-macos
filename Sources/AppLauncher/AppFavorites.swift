import Foundation

/// Persists favorite launcher entries by app `InstalledApp.id` (bundle id or path), in user-defined order.
final class AppFavorites {
    static let shared = AppFavorites()

    private let defaultsKey = "launcherFavoriteAppIdsOrdered"

    private init() {}

    private var storedIds: [String] {
        get { UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Stable ordering for “Favorites” (first starred appears first among favorites).
    var orderedIds: [String] {
        storedIds
    }

    func contains(_ id: String) -> Bool {
        storedIds.contains(id)
    }

    func toggle(_ id: String) {
        var next = storedIds
        if let idx = next.firstIndex(of: id) {
            next.remove(at: idx)
        } else {
            next.append(id)
        }
        storedIds = next
    }

    /// Drops favorites whose apps were uninstalled or rescanned away.
    func prune(toInstalledIds validIds: Set<String>) {
        let filtered = storedIds.filter { validIds.contains($0) }
        if filtered.count != storedIds.count {
            storedIds = filtered
        }
    }
}
