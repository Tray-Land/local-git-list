import Foundation
import Testing
@testable import LocalGitListCore

struct RemoteURLPolicyTests {
    @Test(arguments: [
        ("https://github.com/Tray-Land/tray-git.git", "https://github.com/Tray-Land/tray-git"),
        ("https://user:token@github.com/owner/repo", "https://github.com/owner/repo"),
        ("git@github.com:owner/repo.git", "https://github.com/owner/repo"),
        ("ssh://git@gitlab.example.com:2222/group/sub/repo.git", "https://gitlab.example.com/group/sub/repo"),
        ("git://example.org/repo.git/", "https://example.org/repo"),
        ("http://intranet:8080/scm/repo.git", "http://intranet:8080/scm/repo"),
        ("https://git.example.com:8443/repo", "https://git.example.com:8443/repo"),
        ("git@ssh.dev.azure.com:v3/org/project/repo", "https://dev.azure.com/org/project/_git/repo"),
        ("git@bitbucket.org:team/repo.git", "https://bitbucket.org/team/repo"),
    ])
    func mapsRemotes(remote: String, expected: String) {
        #expect(RemoteURLPolicy.webURL(for: remote)?.absoluteString == expected)
    }

    @Test(arguments: ["", "/Users/me/repo.git", "../other", "file:///tmp/repo", "C:\\repo", "host:", "https://github.com/"])
    func rejectsLocalAndEmpty(remote: String) {
        #expect(RemoteURLPolicy.webURL(for: remote) == nil)
    }
}

struct GitMetadataTests {
    @Test func parsesHead() {
        #expect(GitMetadata.parseHead("ref: refs/heads/main\n") == "main")
        #expect(GitMetadata.parseHead("ref: refs/heads/feature/x") == "feature/x")
        #expect(GitMetadata.parseHead("0123456789abcdef0123456789abcdef01234567") == "0123456")
        #expect(GitMetadata.parseHead("garbage") == nil)
    }

    @Test func prefersOriginThenFirstRemote() {
        let config = """
        [core]
            url = nope
        [remote "upstream"]
            url = git@github.com:up/repo.git
        [remote "origin"]
            fetch = +refs/heads/*:refs/remotes/origin/*
            url = "https://github.com/me/repo.git" ; comment
        """
        #expect(GitMetadata.parseRemoteURL(config) == "https://github.com/me/repo.git")
        #expect(GitMetadata.parseRemoteURL("[remote \"a\"]\n url = x:y # c\n[remote \"b\"]\n url = z") == "x:y")
        #expect(GitMetadata.parseRemoteURL("[core]\n bare = false") == nil)
    }
}

struct GitStatusParserTests {
    @Test func sumsNumstatSkippingBinary() {
        let result = GitStatusParser.parseNumstat("12\t3\ta.swift\n-\t-\timage.png\n1\t0\tb with\ttab\n")
        #expect(result.added == 13)
        #expect(result.removed == 3)
    }

    @Test func readsAheadBehind() {
        let output = "# branch.oid abc\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -5\n"
        #expect(GitStatusParser.parseAheadBehind(output) == (2, 5))
        #expect(GitStatusParser.parseAheadBehind("# branch.head main\n") == (0, 0))
    }
}

struct RepoListPolicyTests {
    private func repo(_ name: String, _ relative: String? = nil) -> GitRepo {
        GitRepo(name: name, path: "/src/\(relative ?? name)", relativePath: relative ?? name, branch: "main", remoteURL: nil, webURL: nil)
    }

    @Test func recentFirstThenNatural() {
        let repos = [repo("b"), repo("a10"), repo("a2"), repo("c")]
        let used = ["/src/c": Date(timeIntervalSince1970: 100)]
        #expect(RepoListPolicy.arrange(repos, lastUsed: used, query: "").map(\.name) == ["c", "a2", "a10", "b"])
    }

    @Test func everyWordMustMatchNameOrPath() {
        let repos = [repo("cli", "tools/cli"), repo("tools-web"), repo("api", "server/api")]
        #expect(RepoListPolicy.arrange(repos, lastUsed: [:], query: "tools").map(\.name) == ["tools-web", "cli"])
        #expect(RepoListPolicy.arrange(repos, lastUsed: [:], query: "TOOLS cli").map(\.name) == ["cli"])
    }

    @Test func favoritesOnly() {
        let repos = [repo("a"), repo("b")]
        #expect(RepoListPolicy.arrange(repos, lastUsed: [:], query: "", onlyPaths: ["/src/b"]).map(\.name) == ["b"])
    }

    @Test func recordUseCapsHistory() {
        var used: [String: Date] = [:]
        for i in 0..<60 { used = RepoListPolicy.recordUse(used, path: "/r\(i)", at: Date(timeIntervalSince1970: Double(i))) }
        #expect(used.count == RepoListPolicy.maxRecent)
        #expect(used["/r0"] == nil)
        #expect(used["/r59"] != nil)
    }
}

struct RepoScannerTests {
    @Test func findsReposWorktreesAndStopsAtRepos() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString).path
        defer { try? fm.removeItem(atPath: root) }

        func makeRepo(_ relative: String, branch: String = "main") throws {
            let git = "\(root)/\(relative)/.git"
            try fm.createDirectory(atPath: git, withIntermediateDirectories: true)
            try "ref: refs/heads/\(branch)\n".write(toFile: "\(git)/HEAD", atomically: true, encoding: .utf8)
            try "[remote \"origin\"]\n\turl = git@github.com:me/\(relative).git\n".write(toFile: "\(git)/config", atomically: true, encoding: .utf8)
        }

        try makeRepo("alpha")
        try makeRepo("alpha/nested")            // inside a repo: not listed
        try makeRepo("group/beta", branch: "dev")
        try makeRepo("a/b/c/d/too-deep")         // five levels down: not listed
        try makeRepo("node_modules")             // skipped name, but is itself a repo
        try fm.createDirectory(atPath: "\(root)/node_modules/pkg/.git", withIntermediateDirectories: true)

        // A worktree of alpha: a .git file pointing into alpha's worktrees dir, config from commondir.
        let worktreeGit = "\(root)/alpha/.git/worktrees/wt"
        try fm.createDirectory(atPath: worktreeGit, withIntermediateDirectories: true)
        try "ref: refs/heads/topic\n".write(toFile: "\(worktreeGit)/HEAD", atomically: true, encoding: .utf8)
        try "../..\n".write(toFile: "\(worktreeGit)/commondir", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: "\(root)/wt", withIntermediateDirectories: true)
        try "gitdir: \(worktreeGit)\n".write(toFile: "\(root)/wt/.git", atomically: true, encoding: .utf8)

        let repos = try RepoScanner.scan(root: root)
        #expect(repos.map(\.relativePath) == ["alpha", "group/beta", "node_modules", "wt"])

        let beta = try #require(repos.first { $0.name == "beta" })
        #expect(beta.branch == "dev")
        #expect(beta.parentPath == "group")
        #expect(beta.webURL?.absoluteString == "https://github.com/me/group/beta")

        let worktree = try #require(repos.first { $0.name == "wt" })
        #expect(worktree.branch == "topic")
        #expect(worktree.webURL?.absoluteString == "https://github.com/me/alpha")
    }
}
