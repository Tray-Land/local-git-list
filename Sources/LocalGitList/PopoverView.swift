import LocalGitListCore
import SwiftUI

/// The popover under the menu bar icon: header, filter field, repo list and footer.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.sourceFolder == nil {
                firstRun
            } else {
                filterField
                Divider()
                repoList
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }
                Divider()
                footer
            }
        }
        .frame(width: 380, height: 520)
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Text("Local Git List")
                .font(.title3.weight(.semibold))
            Spacer()
            Toggle(isOn: $model.favoritesOnly) {
                Image(systemName: model.favoritesOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .help(model.favoritesOnly ? "Show All Repositories" : "Show Favorites Only")
            .keyboardShortcut("l", modifiers: .command)

            Button("Rescan", systemImage: "arrow.clockwise", action: model.rescan)
                .help("Rescan Source Folder")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.sourceFolder == nil || model.isScanning)

            Button("Settings", systemImage: "gearshape", action: model.showSettings)
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var filterField: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $model.query)
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    guard let repo = model.selectedRepo else { return .handled }
                    if press.modifiers.contains(.command) {
                        model.openFolder(repo)
                    } else if press.modifiers.contains(.option) {
                        model.openRemote(repo)
                    } else {
                        model.openTerminal(repo)
                    }
                    return .handled
                }
                .onExitCommand {
                    if model.query.isEmpty { model.dismissPopover() } else { model.query = "" }
                }
            if !model.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onChange(of: model.focusRequest, initial: true) { filterFocused = true }
    }

    @ViewBuilder
    private var repoList: some View {
        let repos = model.visibleRepos
        if repos.isEmpty {
            emptyList
                .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(repos.enumerated()), id: \.element.id) { index, repo in
                            RepoRow(repo: repo, isSelected: index == model.selectedIndex)
                                .id(repo.id)
                                .onTapGesture { model.selectedIndex = index }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selectedIndex) { _, index in
                    guard repos.indices.contains(index) else { return }
                    proxy.scrollTo(repos[index].id)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyList: some View {
        if !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.favoritesOnly {
            ContentUnavailableView("No Favorites", systemImage: "star",
                                   description: Text("Control-click a repository and choose Favorite."))
        } else if model.isScanning {
            ProgressView("Scanning…")
        } else {
            ContentUnavailableView("No Repositories", systemImage: "folder",
                                   description: Text("No git repositories were found in the source folder."))
        }
    }

    private var firstRun: some View {
        ContentUnavailableView {
            Label("Choose a Source Folder", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Pick the folder that holds your git repositories, such as ~/Developer.")
        } actions: {
            Button("Choose Source Folder…", action: model.chooseSourceFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(summary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.isScanning && !model.repos.isEmpty {
                ProgressView().controlSize(.mini)
                Text("Scanning…")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var summary: String {
        let folder = (model.sourceFolder ?? "").abbreviatingWithTildeInPath
        let count = model.repos.count
        return "\(count) \(count == 1 ? "repo" : "repos") in \(folder)"
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private extension String {
    var abbreviatingWithTildeInPath: String { (self as NSString).abbreviatingWithTildeInPath }
}
