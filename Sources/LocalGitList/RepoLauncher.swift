import AppKit

/// A terminal app that opens a new session in a folder when handed one (`open -a App folder`).
struct TerminalApp: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var name: String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }

    static let defaultPath = "/System/Applications/Utilities/Terminal.app"

    private static let knownBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
    ]

    /// The known terminals that are installed.
    static var installed: [TerminalApp] {
        knownBundleIDs.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { TerminalApp(path: $0.path) }
    }
}

enum RepoLauncher {
    struct LaunchError: LocalizedError {
        var errorDescription: String?
    }

    static func openTerminal(at path: String, using appPath: String) throws {
        let appURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: appPath) ? appPath : TerminalApp.defaultPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw LaunchError(errorDescription: "The terminal app at \(appPath) is missing. Choose another in Settings.")
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: path, isDirectory: true)],
                                withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens the folder itself in Finder (not its parent with the folder selected).
    static func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
