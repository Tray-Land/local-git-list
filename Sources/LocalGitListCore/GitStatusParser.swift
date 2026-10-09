import Foundation

/// Parses the output of the git commands run for the status segment.
public enum GitStatusParser {
    /// Arguments (after `git`) that list changed lines per file.
    public static let diffArguments = ["--no-optional-locks", "diff", "HEAD", "--numstat", "--no-renames"]

    /// Arguments (after `git`) that report the branch's upstream distance.
    public static let statusArguments = ["--no-optional-locks", "status", "--porcelain=v2", "--branch", "--untracked-files=no"]

    /// Sums `git diff --numstat` ("12\t3\tpath"). Binary files are reported as "-\t-" and have no
    /// line counts, so they're skipped.
    public static func parseNumstat(_ output: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count >= 3, let a = Int(parts[0]), let r = Int(parts[1]), a >= 0, r >= 0 {
                added = added.addingReportingOverflow(a).overflow ? .max : added + a
                removed = removed.addingReportingOverflow(r).overflow ? .max : removed + r
            }
        }
        return (added, removed)
    }

    /// Reads "# branch.ab +2 -1" from `git status --porcelain=v2 --branch` (ahead 2, behind 1).
    /// The line is absent when the branch has no upstream, which reads as (0, 0).
    public static func parseAheadBehind(_ output: String) -> (ahead: Int, behind: Int) {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("# branch.ab ") else { continue }
            let parts = line.split(separator: " ")
            if parts.count >= 4, parts[2].hasPrefix("+"), parts[3].hasPrefix("-"),
               let ahead = Int(parts[2].dropFirst()), let behind = Int(parts[3].dropFirst()) {
                return (ahead, behind)
            }
        }
        return (0, 0)
    }

    public static func combine(numstat: String, status: String) -> RepoStatus {
        let (added, removed) = parseNumstat(numstat)
        let (ahead, behind) = parseAheadBehind(status)
        return RepoStatus(added: added, removed: removed, behind: behind, ahead: ahead)
    }
}
