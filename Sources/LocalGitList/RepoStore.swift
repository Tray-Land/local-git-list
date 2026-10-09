import Foundation
import LocalGitListCore

/// The last scan of the source folder, kept so the popover opens with a list immediately.
struct RepoScan: Codable, Sendable {
    var root: String
    var scannedAt: Date
    var repos: [GitRepo]
}

/// Caches the scan in Application Support. Reads and writes fail soft: a bad cache just means a
/// fresh scan.
enum RepoStore {
    private static var cacheURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "LocalGitList", directoryHint: .isDirectory)
            .appending(path: "repos.json")
    }

    static func loadCache(root: String) -> RepoScan? {
        guard let data = try? Data(contentsOf: cacheURL),
              let scan = try? JSONDecoder().decode(RepoScan.self, from: data),
              scan.root == root
        else { return nil }
        return scan
    }

    static func saveCache(_ scan: RepoScan) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(scan).write(to: cacheURL, options: .atomic)
        } catch {
            // The cache is an optimization; the scan result is still good.
        }
    }
}
