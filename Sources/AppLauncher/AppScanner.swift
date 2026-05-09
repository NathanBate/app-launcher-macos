import Foundation

enum AppScanner {
    private static let roots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "\(NSHomeDirectory())/Applications", isDirectory: true),
    ]

    /// Recursively finds `.app` bundles under standard install locations (skips descending into bundles).
    static func scan() -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
        ]

        var paths = Set<String>()
        for root in roots {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: options
            ) else {
                continue
            }
            while let item = enumerator.nextObject() as? URL {
                if item.pathExtension == "app" {
                    paths.insert(item.standardizedFileURL.path)
                }
            }
        }

        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Prefers a single URL per bundle identifier; apps without a bundle id are kept by path.
    static func dedupe(urls: [URL]) -> [URL] {
        var byBundle: [String: URL] = [:]
        var noId: [URL] = []

        for url in urls {
            guard let bundle = Bundle(url: url) else {
                noId.append(url)
                continue
            }
            let bid = bundle.bundleIdentifier
            if let bid, !bid.isEmpty {
                if byBundle[bid] == nil {
                    byBundle[bid] = url
                }
            } else {
                noId.append(url)
            }
        }

        return Array(byBundle.values) + noId
    }
}
