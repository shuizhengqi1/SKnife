import StatusMenusCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @EnvironmentObject private var storageStore: StorageMonitorStore
    @EnvironmentObject private var slockStore: SlockMonitorStore
    @EnvironmentObject private var usageStore: UsageMonitorStore
    @State private var selectedModule: ModuleID? = .storage

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedModule)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detailView(for: selectedModuleID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    NotificationCenter.default.post(name: .statusMenusOpenSettings, object: nil)
                } label: {
                    HStack(spacing: 6) {
                        SymbolIcon(symbolName: "gear", size: 16)
                        Text("Settings")
                    }
                }
                .help("Open Settings")
            }
        }
        .task(id: monitorConfigurationID) {
            await configureMonitorStores()
        }
    }

    private var selectedModuleID: ModuleID {
        if let selectedModule, moduleStore.isEnabled(selectedModule) {
            return selectedModule
        }
        return .modules
    }

    private var monitorConfigurationID: String {
        "\(moduleStore.slockRootPath)|\(moduleStore.effectiveRefreshInterval)"
    }

    @MainActor
    private func configureMonitorStores() async {
        await storageStore.loadLatestStorageIndexIfNeeded()
        slockStore.startRefreshLoop(
            rootPath: moduleStore.slockRootPath,
            refreshInterval: moduleStore.effectiveRefreshInterval
        )
        usageStore.startRefreshLoop(refreshInterval: moduleStore.effectiveRefreshInterval)
    }

    @ViewBuilder
    private func detailView(for moduleID: ModuleID) -> some View {
        switch moduleID {
        case .storage:
            StorageView()
        case .slock:
            SlockAgentsView()
        case .usage:
            UsageMonitorView()
        case .modules:
            ModuleManagerView()
        }
    }
}
