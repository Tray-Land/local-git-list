# Local Git List

A native macOS menu bar app for the git repos on your Mac: open a terminal in one, open it in Finder, or open its remote in the browser. It works on your local checkouts, not on hosted features like pull requests and issues. It's a Swift/SwiftUI port of [Tray Git](https://github.com/Tray-Land/tray-git).

## Features

- **Source folder:** finds every working copy up to four folders deep. It stops at each repo, so submodules and vendored checkouts stay out of the list. It skips `node_modules`, `build`, `Pods`, `DerivedData`, dot-folders and symlinks.
- **One-click actions per repo:** Terminal (Terminal, iTerm, Ghostty, Warp or any app you pick in Settings), Finder (double-clicking a row does the same), and Remote. Remote turns https, ssh, `git://` and scp-style remotes into a web URL and drops credentials and ssh ports. It also handles Azure DevOps.
- **Filter:** start typing as soon as the popover opens. Every word must match the name or the path. Use ↑/↓ to move the selection. ↩ opens a terminal, ⌘↩ opens Finder, ⌥↩ opens the remote. Esc clears the filter, then closes the popover.
- **Recent first:** repos you've opened through Local Git List sort to the top. Everything else is in Finder-style name order.
- **Status:** each row shows the branch (or the short commit when HEAD is detached), lines added and removed against `HEAD`, `↓` commits to pull, `↑` commits to push, and the parent folder.
- **Fetch and favorites:** Control-click (or right-click) a row to Fetch, Favorite or Unfavorite, or to copy the path or remote URL. The ★ button (⌘L) shows favorites only.
- **Worktrees:** each worktree is listed as its own entry, and its remote is read from the main repo.
- **Menu bar:** click the icon to toggle the popover. Control-click or right-click it for Open, Settings… and Quit. The icon is Tray Git's pull-request glyph (MIT), drawn as a template image so it follows light and dark menu bars.
- **Settings:** source folder, terminal app, and Open at login (`SMAppService`).
- **Single instance:** launching Local Git List again opens the popover of the copy that's already running.

## Privacy and footprint

- Local Git List makes no network calls of its own. Only Fetch touches the network, and it uses your normal git credentials. It never prompts for a password (`GIT_TERMINAL_PROMPT=0`).
- Scanning reads only `.git/HEAD` and `.git/config`. While the popover is open, Local Git List runs read-only `git status` and `git diff HEAD --numstat` with `--no-optional-locks`, at most once every 30 seconds per repo and at most four at a time.
- Local Git List scans when the popover opens and the last scan is more than five minutes old, when you change the folder, or when you press Rescan (⌘R). The result is cached in `~/Library/Application Support/local.localgitlist.LocalGitList/repos.json`, and preferences are stored in `UserDefaults`.
- Status needs git from Homebrew or the Xcode Command Line Tools. Without git the list still works, just without status.

## Build

Requirements: macOS 14 or later and Xcode 16 or later (Swift 6).

```sh
./build.sh            # builds "build/Local Git List.app" (universal, ad-hoc signed)
./build.sh --install  # also copies it to /Applications and launches it
./build.sh --dmg      # also builds build/LocalGitList.dmg
swift test            # core logic tests
```

### Distributing

Without a certificate the dmg is ad-hoc signed. Users have to approve it once: try to open the app, then System Settings > Privacy & Security > Open Anyway (or `xattr -dr com.apple.quarantine "/Applications/Local Git List.app"`).

For a dmg that opens without warnings, use a Developer ID Application certificate and notarize:

```sh
xcrun notarytool store-credentials notary-profile   # one time
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=notary-profile ./build.sh --dmg
```

## Layout

| Path | What it holds |
|---|---|
| `Sources/LocalGitListCore` | Logic with no UI: `RepoScanner`, `GitMetadata` (`.git` parsing), `RemoteURLPolicy`, `RepoListPolicy`, `GitStatusParser`, `GitService` |
| `Sources/LocalGitList/AppDelegate.swift` | Status item, popover, menu, Settings window, single instance |
| `Sources/LocalGitList/AppModel.swift` | Observable state: preferences, scan, status refresh, fetch, actions |
| `Sources/LocalGitList/PopoverView.swift`, `RepoRow.swift`, `SettingsView.swift` | SwiftUI views |
| `Sources/LocalGitList/RepoLauncher.swift`, `RepoStore.swift` | Terminal and Finder launching, scan cache |
| `Sources/LocalGitList/MenuBarIcon.swift` | The menu bar glyph, from Tray Git's `branding/icon.svg` |
