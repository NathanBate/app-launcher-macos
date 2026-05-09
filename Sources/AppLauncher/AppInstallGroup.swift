import Foundation

/// Install location used for grouping apps in the launcher list.
enum AppInstallGroup: String, CaseIterable, Identifiable {
    case system
    case shared
    case user

    var id: String { rawValue }

    /// Section order in the UI when not searching.
    static let displayOrder: [AppInstallGroup] = [.system, .shared, .user]

    var title: String {
        switch self {
        case .system:
            "System"
        case .shared:
            "Applications"
        case .user:
            "My Applications"
        }
    }

    static func group(for url: URL) -> AppInstallGroup {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let systemRoot = "/System/Applications"
        let userRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path
        if path.hasPrefix(systemRoot) {
            return .system
        }
        if path.hasPrefix(userRoot) {
            return .user
        }
        return .shared
    }
}
