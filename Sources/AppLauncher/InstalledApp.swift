import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let installGroup: AppInstallGroup
    let icon: NSImage

    init(url: URL) {
        self.url = url
        self.installGroup = AppInstallGroup.group(for: url)
        let bundle = Bundle(url: url)
        self.bundleIdentifier = bundle?.bundleIdentifier

        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        self.name = [displayName, bundleName]
            .compactMap { $0 }
            .first { !$0.isEmpty }
            ?? url.deletingPathExtension().lastPathComponent

        self.id = self.bundleIdentifier ?? url.path
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
