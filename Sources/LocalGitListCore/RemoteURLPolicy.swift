import Foundation

/// Turns a git remote URL into the web page for that repo.
public enum RemoteURLPolicy {
    /// Maps https, http, ssh, git:// and scp-style (`git@host:owner/repo.git`) remotes to an https
    /// page, dropping credentials, ports and the `.git` suffix. Returns nil for local paths and
    /// anything else with no web page.
    public static func webURL(for remote: String?) -> URL? {
        guard let remote = remote?.trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty else { return nil }

        var scheme = "https"
        var host: String
        var port: Int?
        var path: String

        if remote.contains("://") {
            guard let components = URLComponents(string: remote),
                  let remoteScheme = components.scheme?.lowercased(),
                  let remoteHost = components.host, !remoteHost.isEmpty
            else { return nil }

            switch remoteScheme {
            case "http": scheme = "http"
            case "https", "ssh", "git", "git+ssh", "ssh+git": break
            default: return nil // file:// and friends
            }

            host = remoteHost
            path = components.path

            // An explicit port belongs to the ssh/git daemon, not the web server, except on http(s).
            if let remotePort = components.port,
               (remoteScheme == "http" && remotePort != 80) || (remoteScheme == "https" && remotePort != 443) {
                port = remotePort
            }
        } else {
            // scp-like syntax: [user@]host:path. Anything with a slash before the colon is a local path.
            guard let colon = remote.firstIndex(of: ":"), remote.distance(from: remote.startIndex, to: colon) > 1 else { return nil }
            if let slash = remote.firstIndex(where: { $0 == "/" || $0 == "\\" }), slash < colon { return nil }

            host = String(remote[..<colon])
            if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
            path = "/" + remote[remote.index(after: colon)...].drop(while: { $0 == "/" })
        }

        guard !host.isEmpty else { return nil }

        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix(".git") { path.removeLast(4) }

        // Azure DevOps ssh remotes: ssh.dev.azure.com:v3/org/project/repo
        let segments = path.split(separator: "/")
        if host.lowercased() == "ssh.dev.azure.com", segments.count == 4, segments[0] == "v3" {
            return URL(string: "https://dev.azure.com/\(segments[1])/\(segments[2])/_git/\(segments[3])")
        }

        guard path.count > 1 else { return nil }

        var result = URLComponents()
        result.scheme = scheme
        result.host = host
        result.port = port
        result.path = path
        return result.url
    }
}
