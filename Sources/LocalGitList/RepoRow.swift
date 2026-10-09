import LocalGitListCore
import SwiftUI

/// One repo: name, branch and status, and the terminal / Finder / remote buttons.
struct RepoRow: View {
    @Environment(AppModel.self) private var model
    let repo: GitRepo
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(repo.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if model.isFavorite(repo) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                    if model.fetching.contains(repo.path) {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("Fetching")
                    }
                }
                caption
            }
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { model.openFolder(repo) }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }

    /// Branch, then lines added/removed and commits to pull/push, then the parent folder.
    private var caption: some View {
        HStack(spacing: 5) {
            if let branch = repo.branch {
                Text(branch)
            }
            if let status = model.statuses[repo.path] {
                if status.added > 0 {
                    Text("+\(status.added)").foregroundStyle(.green)
                }
                if status.removed > 0 {
                    Text("\u{2212}\(status.removed)").foregroundStyle(.red)
                }
                if status.behind > 0 {
                    Text("\u{2193}\(status.behind)").help("\(status.behind) commits to pull")
                }
                if status.ahead > 0 {
                    Text("\u{2191}\(status.ahead)").help("\(status.ahead) commits to push")
                }
            }
            if !repo.parentPath.isEmpty {
                Text(repo.branch == nil ? repo.parentPath : "· \(repo.parentPath)")
                    .truncationMode(.head)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button("Open in Terminal", systemImage: "terminal") { model.openTerminal(repo) }
                .help("Open in Terminal")
            Button("Open in Finder", systemImage: "folder") { model.openFolder(repo) }
                .help("Open in Finder")
            Button("Open Remote", systemImage: "globe") { model.openRemote(repo) }
                .help(repo.remoteHelp)
                .disabled(repo.webURL == nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(IconButtonStyle())
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Fetch") { model.fetch(repo) }
            .disabled(model.fetching.contains(repo.path) || repo.remoteURL == nil)
        Button(model.isFavorite(repo) ? "Unfavorite" : "Favorite") { model.toggleFavorite(repo) }
        Divider()
        Button("Open in Terminal") { model.openTerminal(repo) }
        Button("Open in Finder") { model.openFolder(repo) }
        Button("Open Remote") { model.openRemote(repo) }
            .disabled(repo.webURL == nil)
        Divider()
        Button("Copy Path") { copy(repo.path) }
        if let remote = repo.remoteURL {
            Button("Copy Remote URL") { copy(remote) }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// A borderless icon button with a hover highlight, like toolbar buttons.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration)
    }

    private struct IconButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 14))
                .frame(width: 28, height: 26)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .background(
                    Color.primary.opacity(configuration.isPressed ? 0.15 : isHovered && isEnabled ? 0.08 : 0),
                    in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
