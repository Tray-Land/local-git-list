import AppKit
import LocalGitListCore
import Observation

/// Everything the popover and Settings show: the scanned repos, their git status, and the user's
/// preferences. Scanning and status reads only start while the popover is open.
@MainActor
@Observable
final class AppModel {
    private static let rescanAfter: TimeInterval = 5 * 60
    private static let statusRefreshAfter: TimeInterval = 30
    private static let maxConcurrentStatusReads = 4

    // MARK: Preferences

    private let defaults = UserDefaults.standard

    var sourceFolder: String? {
        didSet {
            defaults.set(sourceFolder, forKey: Keys.sourceFolder)
            guard sourceFolder != oldValue else { return }
            repos = []
            statuses = [:]
            statusReadAt = [:]
            scannedAt = nil
            rescan()
        }
    }

    /// The app that opens repos as a terminal session; Terminal unless the user picked another.
    var terminalAppPath: String {
        didSet { defaults.set(terminalAppPath, forKey: Keys.terminalAppPath) }
    }

    private(set) var lastUsed: [String: Date] {
        didSet { defaults.set(lastUsed, forKey: Keys.lastUsed) }
    }

    private(set) var favorites: Set<String> {
        didSet { defaults.set(Array(favorites).sorted(), forKey: Keys.favorites) }
    }

    var favoritesOnly: Bool {
        didSet {
            defaults.set(favoritesOnly, forKey: Keys.favoritesOnly)
            selectedIndex = 0
        }
    }

    // MARK: State

    private(set) var repos: [GitRepo] = []
    private(set) var scannedAt: Date?
    private(set) var isScanning = false
    private(set) var statuses: [String: RepoStatus] = [:]
    private(set) var fetching: Set<String> = []
    var errorMessage: String?

    var query = "" {
        didSet { selectedIndex = 0 }
    }
    var selectedIndex = 0

    /// Bumped each time the popover opens so the filter field takes focus.
    private(set) var focusRequest = 0

    @ObservationIgnored private var statusReadAt: [String: Date] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    // Hooks into the status item controller.
    @ObservationIgnored var dismissPopover: () -> Void = {}
    @ObservationIgnored var setPopoverPinned: (Bool) -> Void = { _ in }
    @ObservationIgnored var showSettings: () -> Void = {}

    init() {
        sourceFolder = defaults.string(forKey: Keys.sourceFolder)
        terminalAppPath = defaults.string(forKey: Keys.terminalAppPath) ?? TerminalApp.defaultPath
        lastUsed = defaults.dictionary(forKey: Keys.lastUsed) as? [String: Date] ?? [:]
        favorites = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])
        favoritesOnly = defaults.bool(forKey: Keys.favoritesOnly)
    }

    var visibleRepos: [GitRepo] {
        RepoListPolicy.arrange(repos, lastUsed: lastUsed, query: query, onlyPaths: favoritesOnly ? favorites : nil)
    }

    var selectedRepo: GitRepo? {
        let visible = visibleRepos
        return visible.indices.contains(selectedIndex) ? visible[selectedIndex] : visible.first
    }

    func isFavorite(_ repo: GitRepo) -> Bool { favorites.contains(repo.path) }

    // MARK: Popover lifecycle

    func popoverWillShow() {
        query = ""
        focusRequest += 1
        guard let sourceFolder else { return }

        if repos.isEmpty, let cached = RepoStore.loadCache(root: sourceFolder) {
            repos = cached.repos
            scannedAt = cached.scannedAt
        }
        if scannedAt.map({ Date.now.timeIntervalSince($0) > Self.rescanAfter }) ?? true {
            rescan()
        } else {
            refreshStatuses()
        }
    }

    func popoverDidClose() {
        statusTask?.cancel()
        statusTask = nil
    }

    // MARK: Scanning and status

    func rescan() {
        guard let root = sourceFolder else { return }
        scanTask?.cancel()
        isScanning = true
        scanTask = Task {
            let scan = await Task.detached(priority: .userInitiated) { () -> RepoScan? in
                guard let repos = try? RepoScanner.scan(root: root) else { return nil }
                let scan = RepoScan(root: root, scannedAt: .now, repos: repos)
                RepoStore.saveCache(scan)
                return scan
            }.value

            guard !Task.isCancelled, let scan, scan.root == sourceFolder else { return }
            repos = scan.repos
            scannedAt = scan.scannedAt
            isScanning = false
            let paths = Set(repos.map(\.path))
            statuses = statuses.filter { paths.contains($0.key) }
            refreshStatuses()
        }
    }

    /// Reads git status for repos not read in the last 30 seconds, top of the list first.
    func refreshStatuses() {
        statusTask?.cancel()
        let now = Date.now
        let stale = visibleRepos.map(\.path).filter { path in
            statusReadAt[path].map { now.timeIntervalSince($0) > Self.statusRefreshAfter } ?? true
        }
        guard !stale.isEmpty, GitService.executable != nil else { return }

        statusTask = Task {
            await withTaskGroup(of: (String, RepoStatus?).self) { group in
                var pending = stale.makeIterator()
                func startNext() -> Bool {
                    guard !Task.isCancelled, let path = pending.next() else { return false }
                    group.addTask { (path, await GitService.readStatus(repoPath: path)) }
                    return true
                }
                for _ in 0..<Self.maxConcurrentStatusReads where !startNext() { break }
                for await (path, status) in group {
                    statusReadAt[path] = .now
                    statuses[path] = status
                    _ = startNext()
                }
            }
        }
    }

    func fetch(_ repo: GitRepo) {
        guard !fetching.contains(repo.path) else { return }
        fetching.insert(repo.path)
        Task {
            defer { fetching.remove(repo.path) }
            do {
                try await GitService.fetch(repoPath: repo.path)
                statuses[repo.path] = await GitService.readStatus(repoPath: repo.path)
                statusReadAt[repo.path] = .now
            } catch {
                errorMessage = "Couldn't fetch \(repo.name): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Actions

    func toggleFavorite(_ repo: GitRepo) {
        if favorites.contains(repo.path) {
            favorites.remove(repo.path)
        } else {
            favorites.insert(repo.path)
        }
    }

    func moveSelection(by offset: Int) {
        let count = visibleRepos.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
    }

    func openTerminal(_ repo: GitRepo) {
        perform(on: repo) { try RepoLauncher.openTerminal(at: repo.path, using: self.terminalAppPath) }
    }

    func openFolder(_ repo: GitRepo) {
        perform(on: repo) { RepoLauncher.openFolder(repo.path) }
    }

    func openRemote(_ repo: GitRepo) {
        guard let url = repo.webURL else { return }
        perform(on: repo) { NSWorkspace.shared.open(url) }
    }

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your git repositories."
        if let sourceFolder { panel.directoryURL = URL(fileURLWithPath: sourceFolder) }

        // The popover would close as soon as the panel takes focus.
        setPopoverPinned(true)
        defer { setPopoverPinned(false) }
        if panel.runModal() == .OK, let url = panel.url {
            sourceFolder = url.path
        }
    }

    private func perform(on repo: GitRepo, _ action: @escaping () throws -> Void) {
        do {
            try action()
            lastUsed = RepoListPolicy.recordUse(lastUsed, path: repo.path)
            dismissPopover()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum Keys {
        static let sourceFolder = "SourceFolder"
        static let terminalAppPath = "TerminalAppPath"
        static let lastUsed = "LastUsed"
        static let favorites = "Favorites"
        static let favoritesOnly = "FavoritesOnly"
    }
}
