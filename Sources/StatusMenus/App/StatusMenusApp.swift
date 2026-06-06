import AppKit
import StatusMenusCore
import SwiftUI

extension Notification.Name {
    static let statusMenusOpenSettings = Notification.Name("StatusMenus.openSettings")
}

@main
@MainActor
final class StatusMenusApplication: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: StatusMenusApplication?

    private let moduleStore = ModuleStore()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var defaultsObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = StatusMenusApplication()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        observePreferences()
        showMainWindow()
        updateStatusItem()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    @objc private func showMainWindowAction(_ sender: Any?) {
        showMainWindow()
    }

    @objc private func openSettingsWindow(_ sender: Any?) {
        if settingsWindow == nil {
            let view = SettingsView()
                .environmentObject(moduleStore)
                .frame(width: 500)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "StatusMenus Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let view = ContentView()
                .environmentObject(moduleStore)
                .frame(minWidth: 900, minHeight: 620)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "StatusMenus"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            menuItem(
                title: "Settings...",
                action: #selector(openSettingsWindow(_:)),
                keyEquivalent: ",",
                target: self
            )
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            menuItem(
                title: "Quit StatusMenus",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q",
                target: NSApp
            )
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func observePreferences() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .statusMenusOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openSettingsWindow(nil)
            }
        }
    }

    private func updateStatusItem() {
        let shouldShow = UserDefaults.standard.bool(forKey: "StatusMenus.showMenuBarStatus")
        if shouldShow {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.title = "StatusMenus"
                item.menu = statusMenu()
                statusItem = item
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            menuItem(
                title: "Open StatusMenus",
                action: #selector(showMainWindowAction(_:)),
                keyEquivalent: "",
                target: self
            )
        )
        menu.addItem(
            menuItem(
                title: "Settings...",
                action: #selector(openSettingsWindow(_:)),
                keyEquivalent: "",
                target: self
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            menuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "",
                target: NSApp
            )
        )
        return menu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }
}
