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
    private var statusRefreshTask: Task<Void, Never>?
    private var statusRefreshConfiguration: String?

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
        stopStatusRefreshLoop()
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
                item.button?.title = "SKnife"
                item.menu = statusMenu(summary: nil)
                statusItem = item
            }
            startStatusRefreshLoopIfNeeded()
        } else if let statusItem {
            stopStatusRefreshLoop()
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func statusMenu(summary: MenuBarStatusSummary?) -> NSMenu {
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

        if let summary {
            for line in summary.menuLines {
                menu.addItem(disabledMenuItem(title: line))
            }
        } else {
            menu.addItem(disabledMenuItem(title: "Refreshing..."))
        }
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

    private func startStatusRefreshLoopIfNeeded() {
        let configuration = "\(moduleStore.slockRootPath)|\(moduleStore.effectiveRefreshInterval)"
        guard statusRefreshTask == nil || statusRefreshConfiguration != configuration else {
            return
        }

        statusRefreshTask?.cancel()
        statusRefreshConfiguration = configuration
        statusRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    break
                }

                await self.refreshStatusMenu()

                do {
                    try await Task.sleep(nanoseconds: self.refreshNanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    private func stopStatusRefreshLoop() {
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        statusRefreshConfiguration = nil
    }

    private func refreshStatusMenu() async {
        guard statusItem != nil else {
            return
        }

        let root = URL(fileURLWithPath: NSString(string: moduleStore.slockRootPath).expandingTildeInPath)
        let summary = await Task.detached(priority: .utility) {
            let processOutput = (try? Shell.live.run(["/bin/ps", "-axo", "pid,etime,pcpu,pmem,command"])) ?? ""
            let slock = try? SlockDiscoveryService().snapshot(rootURL: root, processOutput: processOutput)
            let usage = UsageService().snapshot(processOutput: processOutput)
            return MenuBarStatusSummary(slock: slock, usage: usage)
        }.value

        guard !Task.isCancelled else {
            return
        }

        statusItem?.button?.title = summary.buttonTitle
        statusItem?.menu = statusMenu(summary: summary)
    }

    private var refreshNanoseconds: UInt64 {
        UInt64(moduleStore.effectiveRefreshInterval * 1_000_000_000)
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    private func disabledMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
