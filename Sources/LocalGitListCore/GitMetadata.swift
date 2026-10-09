import Foundation

/// Reads the little the list needs (branch and remote) straight from the `.git` files, so scanning
/// never spawns git and works without git installed.
public enum GitMetadata {
    /// The git directory for a working copy: `.git` itself, or the target of a `.git` file
    /// (`gitdir: ...`) as used by worktrees and submodules.
    public static func gitDir(forWorkingCopy workingCopy: String) -> String? {
        let dotGit = (workingCopy as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }

        guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            text.lowercased().hasPrefix("gitdir:")
        else { return nil }

        let target = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let full = resolve(target, relativeTo: workingCopy)
        return directoryExists(full) ? full : nil
    }

    /// The shared git directory: worktrees keep their config in the main repo's (`commondir`).
    public static func commonDir(_ gitDir: String) -> String {
        let commonFile = (gitDir as NSString).appendingPathComponent("commondir")
        if let target = try? String(contentsOfFile: commonFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
            return resolve(target, relativeTo: gitDir)
        }
        return gitDir
    }

    public static func readBranch(gitDir: String) -> String? {
        let head = (gitDir as NSString).appendingPathComponent("HEAD")
        return (try? String(contentsOfFile: head, encoding: .utf8)).flatMap(parseHead)
    }

    public static func readRemoteURL(gitDir: String) -> String? {
        let config = (commonDir(gitDir) as NSString).appendingPathComponent("config")
        return (try? String(contentsOfFile: config, encoding: .utf8)).flatMap(parseRemoteURL)
    }

    /// "ref: refs/heads/main" → "main"; a detached commit id → its first 7 characters.
    public static func parseHead(_ head: String) -> String? {
        let head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref:") {
            let reference = head.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let heads = "refs/heads/"
            return reference.hasPrefix(heads) ? String(reference.dropFirst(heads.count)) : reference
        }
        return head.count >= 7 && head.allSatisfy(\.isHexDigit) ? String(head.prefix(7)) : nil
    }

    /// The `url` of `[remote "origin"]`, or of the first remote if there's no origin.
    public static func parseRemoteURL(_ config: String) -> String? {
        var currentRemote: String?
        var first: String?

        for rawLine in config.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let c = line.first, c != "#", c != ";" else { continue }

            if c == "[" {
                currentRemote = parseRemoteSection(line)
                continue
            }
            guard let currentRemote, let equals = line.firstIndex(of: "="), equals > line.startIndex else { continue }
            guard line[..<equals].trimmingCharacters(in: .whitespaces).lowercased() == "url" else { continue }

            let value = stripValue(String(line[line.index(after: equals)...]))
            guard !value.isEmpty else { continue }
            if currentRemote == "origin" { return value }
            if first == nil { first = value }
        }
        return first
    }

    // [remote "origin"] → origin; any other section → nil.
    private static func parseRemoteSection(_ line: String) -> String? {
        var inner = line.dropFirst()
        if let close = inner.firstIndex(of: "]") { inner = inner[..<close] }
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("remote"), trimmed.count > 6 else { return nil }
        let rest = trimmed.dropFirst(6)
        guard rest.first?.isWhitespace == true else { return nil }
        return rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func stripValue(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.first == "\"" {
            let rest = value.dropFirst()
            return String(rest[..<(rest.firstIndex(of: "\"") ?? rest.endIndex)])
        }
        // Inline comments start with # or ; outside quotes.
        let end = value.firstIndex(where: { $0 == "#" || $0 == ";" }) ?? value.endIndex
        return value[..<end].trimmingCharacters(in: .whitespaces)
    }

    private static func resolve(_ path: String, relativeTo base: String) -> String {
        let joined = path.hasPrefix("/") ? path : (base as NSString).appendingPathComponent(path)
        return (joined as NSString).standardizingPath
    }

    private static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
