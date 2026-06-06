import AppKit
import StatusMenusCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
@MainActor
struct StatusMenusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var moduleStore = ModuleStore()

    var body: some Scene {
        WindowGroup("StatusMenus", id: "main") {
            ContentView()
                .environmentObject(moduleStore)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings...")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(moduleStore)
        }

        MenuBarExtra(
            "StatusMenus",
            systemImage: "rectangle.3.group",
            isInserted: $moduleStore.showMenuBarStatus
        ) {
            MenuBarStatusView()
                .environmentObject(moduleStore)
        }
        .menuBarExtraStyle(.menu)
    }
}
