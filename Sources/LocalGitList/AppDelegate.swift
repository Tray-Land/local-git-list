import AppKit
import SwiftUI

/// Owns the menu bar item, its popover and the Settings window. Local Git List has no Dock icon or main
/// window (`LSUIElement`); clicking the icon toggles the popover and Control- or right-clicking it
/// shows a menu.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Single instance: hand off to a copy that's already running (it gets a reopen event).
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        if let running = others.first, let url = running.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // A fixed size: letting the hosting controller resize a shown popover grows it off the top of the screen.
        let content = NSHostingController(rootView: PopoverView().environment(model))
        content.sizingOptions = []
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 380, height: 520)

        model.dismissPopover = { [weak self] in self?.popover.performClose(nil) }
        model.setPopoverPinned = { [weak self] pinned in
            self?.popover.behavior = pinned ? .applicationDefined : .transient
            if !pinned { self?.popover.contentViewController?.view.window?.makeKey() }
        }
        model.showSettings = { [weak self] in self?.showSettings() }

        // First run: open straight to "Choose Source Folder".
        if model.sourceFolder == nil {
            DispatchQueue.main.async { self.showPopover() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Local Git List", action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Local Git List", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attaching the menu for a single click shows it the standard way, under the icon.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() { showPopover() }
    @objc private func settingsFromMenu() { showSettings() }

    // MARK: Popover

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        model.popoverWillShow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        model.popoverDidClose()
    }

    // MARK: Settings

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(model))
            controller.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: controller)
            window.title = "Local Git List Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
