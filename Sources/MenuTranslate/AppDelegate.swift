import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = TranslatorModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An accessory app shows no menu bar, but AppKit still routes ⌘-key
        // equivalents through the main menu — and that is the only thing that
        // gives the text editor ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z.
        NSApp.mainMenu = Self.makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MenuTranslate"
        }

        popover = NSPopover()
        // Left as application-defined so the language pickers — which are
        // popovers of their own — do not dismiss the panel underneath them.
        // applicationLostFocus() stands in for the transient behaviour.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 400, height: 246)
        popover.contentViewController = NSHostingController(
            rootView: TranslatePanel(model: model, onQuit: { NSApp.terminate(nil) })
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationLostFocus),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.synchronize()
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        model.panelDidOpen()
        installKeyMonitor()
    }

    private func closePanel() {
        // close() rather than performClose(): dismissal is ours to decide here,
        // not something to route back through the popover's behaviour.
        popover.close()
        removeKeyMonitor()
    }

    @objc private func applicationLostFocus() {
        if popover.isShown { closePanel() }
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
    }

    private func showContextMenu() {
        if popover.isShown { closePanel() }

        let menu = NSMenu()

        let launch = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MenuTranslate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.set(enabled: !LoginItem.isEnabled)
    }

    // MARK: - Panel-wide keys

    /// Escape and ⌘↩ have no menu item to hang off. Everything else — including
    /// ⌘A and the clipboard keys — is passed through to the main menu.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.closePanel()
                return nil
            }
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                self.model.translateNow()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Selectors are built from strings because the Cocoa text-editing actions
    /// are dispatched to whatever the first responder happens to be, and
    /// `#selector(NSText.copy(_:))` collides with `NSObject.copy()`.
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MenuTranslate", action: Selector(("terminate:")), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }

    private static func menuBarIcon() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        for name in ["translate", "character.bubble", "globe"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "MenuTranslate") {
                let sized = image.withSymbolConfiguration(configuration) ?? image
                sized.isTemplate = true
                return sized
            }
        }
        return nil
    }
}
