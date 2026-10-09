import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = Self.isLoginItem
    @State private var loginItemError: String?

    private static let chooseOtherTag = "__choose-other__"

    var body: some View {
        Form {
            Section {
                LabeledContent("Source folder") {
                    HStack {
                        Text(model.sourceFolder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: model.chooseSourceFolder)
                    }
                }
            } footer: {
                Text("Local Git List lists every git repository up to four folders deep.")
                    .foregroundStyle(.secondary)
            }

            Section {
                terminalPicker
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            } footer: {
                if let loginItemError {
                    Text(loginItemError).foregroundStyle(.red)
                } else if SMAppService.mainApp.status == .requiresApproval {
                    Text("Allow Local Git List in System Settings > General > Login Items.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Button("Quit Local Git List") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var terminalPicker: some View {
        let selection = Binding<String>(
            get: { model.terminalAppPath },
            set: { newValue in
                if newValue == Self.chooseOtherTag {
                    chooseTerminalApp()
                } else {
                    model.terminalAppPath = newValue
                }
            })

        var apps = TerminalApp.installed
        if !apps.contains(where: { $0.path == model.terminalAppPath }) {
            apps.append(TerminalApp(path: model.terminalAppPath))
        }

        return Picker("Open terminals with", selection: selection) {
            ForEach(apps) { app in
                Label {
                    Text(app.name)
                } icon: {
                    Image(nsImage: app.icon.resized(to: 16))
                }
                .tag(app.path)
            }
            Divider()
            Text("Other…").tag(Self.chooseOtherTag)
        }
    }

    private func chooseTerminalApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.terminalAppPath = url.path
        }
    }

    // Registering can leave the item waiting for approval in System Settings; that still counts as on.
    private static var isLoginItem: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != Self.isLoginItem else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = Self.isLoginItem
    }
}

private extension NSImage {
    func resized(to side: CGFloat) -> NSImage {
        let image = copy() as! NSImage
        image.size = NSSize(width: side, height: side)
        return image
    }
}
