import AppKit
import StatusMenusCore
import SwiftUI

struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var moduleStore: ModuleStore
    @State private var slockStatus: ModuleStatus = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Open StatusMenus") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            HStack {
                SymbolIcon(symbolName: "square.grid.2x2", size: 14)
                Text("Modules: \(moduleStore.enabledDescriptors.count)")
            }
            HStack {
                SymbolIcon(symbolName: "person.2", size: 14)
                Text("Slock: \(slockStatus.label)")
            }

            Button("Refresh") {
                refresh()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let root = URL(fileURLWithPath: NSString(string: moduleStore.slockRootPath).expandingTildeInPath)
        slockStatus = (try? SlockDiscoveryService().liveSnapshot(rootURL: root).status) ?? .unavailable
    }
}
