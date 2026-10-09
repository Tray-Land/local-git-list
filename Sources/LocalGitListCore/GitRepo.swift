import Foundation

/// A working copy found under the source folder.
public struct GitRepo: Codable, Hashable, Identifiable, Sendable {
    /// The repo's folder name.
    public let name: String
    /// Full path of the working copy.
    public let path: String
    /// Path relative to the source folder ("." when the folder itself is the repo).
    public let relativePath: String
    /// Checked-out branch, a short commit id when detached, or nil if unreadable.
    public let branch: String?
    /// The fetch URL of `origin` (or the first remote), as written in the config.
    public let remoteURL: String?
    /// A browser URL for the remote, or nil when it has no web page (local path, unknown scheme).
    public let webURL: URL?

    public var id: String { path }

    public init(name: String, path: String, relativePath: String, branch: String?, remoteURL: String?, webURL: URL?) {
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.branch = branch
        self.remoteURL = remoteURL
        self.webURL = webURL
    }

    /// The folder above the repo, relative to the source folder; empty at the top level.
    public var parentPath: String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    public var remoteHelp: String {
        if let webURL { return "Open \(webURL.absoluteString)" }
        if let remoteURL { return "No web page for \(remoteURL)" }
        return "No remote"
    }
}

/// What `git` reports for a working copy.
public struct RepoStatus: Codable, Hashable, Sendable {
    /// Lines added in the working tree and index, relative to HEAD.
    public var added: Int
    /// Lines removed in the working tree and index, relative to HEAD.
    public var removed: Int
    /// Commits on the upstream branch that aren't local yet (to pull).
    public var behind: Int
    /// Local commits the upstream branch doesn't have (to push).
    public var ahead: Int

    public init(added: Int = 0, removed: Int = 0, behind: Int = 0, ahead: Int = 0) {
        self.added = added
        self.removed = removed
        self.behind = behind
        self.ahead = ahead
    }

    public var isClean: Bool { added == 0 && removed == 0 && behind == 0 && ahead == 0 }
}
