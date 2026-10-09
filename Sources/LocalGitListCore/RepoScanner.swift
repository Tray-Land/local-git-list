import Foundation

/// Finds git working copies under a folder.
public enum RepoScanner {
    public static let defaultMaxDepth = 4

    // Big trees that never hold a repo of their own; skipped unless the folder itself is a repo.
    private static let skippedNames: Set<String> = [
        "node_modules", "bin", "obj", "packages", "vendor", "target", "dist", "out", "build",
        "__pycache__", "venv", "Pods", "Carthage", "DerivedData", "Library",
    ].reduce(into: []) { $0.insert($1.lowercased()) }

    /// Walks `root` up to `maxDepth` folders deep. A repo is listed and not descended into, so
    /// submodules and vendored checkouts stay out of the list. Symlinks are never followed, since
    /// they can loop or point outside the source folder. Results are sorted by name.
    public static func scan(root: String, maxDepth: Int = defaultMaxDepth) throws -> [GitRepo] {
        let root = (root as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }

        var repos: [GitRepo] = []
        var pending: [(path: String, depth: Int)] = [(root, 0)]
        var next = 0

        while next < pending.count {
            try Task.checkCancellation()
            let (dir, depth) = pending[next]
            next += 1

            if let repo = read(root: root, dir: dir) {
                repos.append(repo)
                continue
            }
            guard depth < maxDepth else { continue }

            for name in childDirectoryNames(of: dir) where name != ".git" {
                let child = (dir as NSString).appendingPathComponent(name)

                // A skipped name can still be a repo itself; check that before skipping it.
                if skippedNames.contains(name.lowercased()) || (name.hasPrefix(".") && name.count > 1) || name.hasSuffix(".app") {
                    if let repo = read(root: root, dir: child) { repos.append(repo) }
                    continue
                }
                pending.append((child, depth + 1))
            }
        }

        return repos.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reads one working copy, or returns nil if `dir` isn't one.
    public static func read(root: String, dir: String) -> GitRepo? {
        guard let gitDir = GitMetadata.gitDir(forWorkingCopy: dir) else { return nil }

        let remote = GitMetadata.readRemoteURL(gitDir: gitDir)
        let name = (dir as NSString).lastPathComponent
        return GitRepo(
            name: name.isEmpty ? dir : name,
            path: dir,
            relativePath: relativePath(of: dir, under: root),
            branch: GitMetadata.readBranch(gitDir: gitDir),
            remoteURL: remote,
            webURL: RemoteURLPolicy.webURL(for: remote))
    }

    // Names rather than URLs: the URLs come back with symlinks in the parent resolved
    // (/var → /private/var), which would no longer sit under `root`.
    private static func childDirectoryNames(of dir: String) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir, isDirectory: true), includingPropertiesForKeys: keys)
        else { return [] }

        return children.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true
            else { return nil }
            return url.lastPathComponent
        }
    }

    private static func relativePath(of dir: String, under root: String) -> String {
        if dir == root { return "." }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return dir.hasPrefix(prefix) ? String(dir.dropFirst(prefix.count)) : dir
    }
}
