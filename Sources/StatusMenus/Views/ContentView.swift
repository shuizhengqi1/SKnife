import StatusMenusCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var moduleStore: ModuleStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selectedModuleBinding)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detailView(for: moduleStore.selectedModule)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                .help("Open Settings")
            }
        }
        .onAppear {
            if !moduleStore.isEnabled(moduleStore.selectedModule) {
                moduleStore.selectedModule = .modules
            }
        }
    }

    private var selectedModuleBinding: Binding<ModuleID?> {
        Binding<ModuleID?>(
            get: { moduleStore.selectedModule },
            set: { newValue in
                if let newValue {
                    moduleStore.selectedModule = newValue
                }
            }
        )
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
