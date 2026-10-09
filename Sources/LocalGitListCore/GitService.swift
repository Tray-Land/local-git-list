import Foundation

public enum GitError: LocalizedError {
    case gitNotFound
    case timedOut
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound: "git was not found. Install the Xcode Command Line Tools (xcode-select --install) or Homebrew git."
        case .timedOut: "git fetch took longer than two minutes and was stopped."
        case .failed(let message): message
        }
    }
}

/// Runs git for the status segment and for Fetch. Everything else reads `.git` files directly;
/// these two need git's own diff and network code. Never prompts for credentials.
public enum GitService {
    private static let statusTimeout: TimeInterval = 30
    private static let fetchTimeout: TimeInterval = 120

    /// Apps launched from Finder get a minimal PATH, so look in the usual places. `/usr/bin/git` is
    /// only used when developer tools are installed; otherwise it's a stub that shows an install dialog.
    public static let executable: URL? = {
        let fm = FileManager.default
        for candidate in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        let developerDirs = ["/Library/Developer/CommandLineTools", "/Applications/Xcode.app/Contents/Developer"]
        if developerDirs.contains(where: { fm.isExecutableFile(atPath: $0 + "/usr/bin/git") }) {
            return URL(fileURLWithPath: "/usr/bin/git")
        }
        return nil
    }()

    /// Reads changed lines and commits ahead/behind; nil when git isn't available or fails.
    public static func readStatus(repoPath: String) async -> RepoStatus? {
        guard let status = await run(GitStatusParser.statusArguments, in: repoPath, timeout: statusTimeout),
              status.exitCode == 0
        else { return nil }

        // A repo with no commits has no HEAD to diff against; that just means no changed lines.
        let diff = await run(GitStatusParser.diffArguments, in: repoPath, timeout: statusTimeout)
        return GitStatusParser.combine(numstat: diff?.exitCode == 0 ? diff!.output : "", status: status.output)
    }

    /// Runs `git fetch`; throws with git's message when it fails.
    public static func fetch(repoPath: String) async throws {
        guard let result = await run(["fetch", "--quiet"], in: repoPath, timeout: fetchTimeout) else { throw GitError.gitNotFound }
        if result.timedOut { throw GitError.timedOut }
        if result.exitCode != 0 {
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(message.isEmpty ? "git fetch exited with code \(result.exitCode)." : message)
        }
    }

    private struct Result: Sendable {
        var exitCode: Int32
        var output: String
        var error: String
        var timedOut: Bool
    }

    /// Runs git off the main thread. Returns nil when git can't be started.
    private static func run(_ arguments: [String], in directory: String, timeout: TimeInterval) async -> Result? {
        guard let executable else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)

                var environment = ProcessInfo.processInfo.environment
                // Fail instead of waiting for a password nobody can type.
                environment["GIT_TERMINAL_PROMPT"] = "0"
                environment["GIT_OPTIONAL_LOCKS"] = "0"
                process.environment = environment

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let timedOut = Box(false)
                let timer = DispatchWorkItem {
                    if process.isRunning {
                        timedOut.value = true
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                // Drain stderr concurrently so neither pipe can fill up and stall git.
                let errorData = Box(Data())
                let errorDrained = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    errorData.value = stderr.fileHandleForReading.readDataToEndOfFile()
                    errorDrained.signal()
                }
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                errorDrained.wait()
                process.waitUntilExit()

                timer.cancel()

                continuation.resume(returning: Result(
                    exitCode: process.terminationStatus,
                    output: String(decoding: outputData, as: UTF8.self),
                    error: String(decoding: errorData.value, as: UTF8.self),
                    timedOut: timedOut.value))
            }
        }
    }
}

/// Hands a value between the dispatch queues above; each one is written before it's read.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) { _value = value }

    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
