import Foundation

/// Orders and filters the repo list for the popover.
public enum RepoListPolicy {
    /// How many recently used repos are remembered.
    public static let maxRecent = 50

    /// Name-prefix matches for the first word first, then recently used repos (newest first), then
    /// the rest by name. With a query, keeps repos whose name or relative path contains every word.
    /// When `onlyPaths` is given, only repos at those paths are kept.
    public static func arrange(
        _ repos: [GitRepo],
        lastUsed: [String: Date],
        query: String,
        onlyPaths: Set<String>? = nil
    ) -> [GitRepo] {
        let words = query.split(separator: " ").map(String.init)
        let first = words.first?.lowercased() ?? ""

        let filtered = repos.filter { repo in
            (onlyPaths?.contains(repo.path) ?? true) && words.allSatisfy { matches(repo, $0) }
        }

        return filtered.sorted { a, b in
            let aPrefix = !first.isEmpty && a.name.lowercased().hasPrefix(first)
            let bPrefix = !first.isEmpty && b.name.lowercased().hasPrefix(first)
            if aPrefix != bPrefix { return aPrefix }

            let aUsed = lastUsed[a.path] ?? .distantPast
            let bUsed = lastUsed[b.path] ?? .distantPast
            if aUsed != bUsed { return aUsed > bUsed }

            let byName = a.name.localizedStandardCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
        }
    }

    /// Records a use and drops the oldest entries past `maxRecent`.
    public static func recordUse(_ lastUsed: [String: Date], path: String, at now: Date = .now) -> [String: Date] {
        var updated = lastUsed
        updated[path] = now
        guard updated.count > maxRecent else { return updated }
        return Dictionary(uniqueKeysWithValues: updated.sorted { $0.value > $1.value }.prefix(maxRecent).map { ($0.key, $0.value) })
    }

    private static func matches(_ repo: GitRepo, _ word: String) -> Bool {
        repo.name.localizedCaseInsensitiveContains(word) || repo.relativePath.localizedCaseInsensitiveContains(word)
    }
}
