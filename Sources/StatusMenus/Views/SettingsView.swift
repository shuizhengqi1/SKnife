import StatusMenusCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var moduleStore: ModuleStore

    var body: some View {
        Form {
            Section("Modules") {
                ForEach(ModuleRegistry.builtIns) { module in
                    Toggle(isOn: enabledBinding(for: module.id)) {
                        HStack(spacing: 8) {
                            SymbolIcon(symbolName: module.symbolName, size: 16)
                            Text(module.title)
                        }
                    }
                    .disabled(module.id == .modules)
                }
            }

            Section("Status") {
                Toggle("Show menu bar status", isOn: $moduleStore.showMenuBarStatus)

                Picker("Refresh interval", selection: $moduleStore.refreshInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                }
                .pickerStyle(.menu)
            }

            Section("Slock") {
                TextField("Slock root", text: $moduleStore.slockRootPath)
                    .textFieldStyle(.roundedBorder)
                Text("Default: ~/.slock. The app scans agents and machines below this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 500)
    }

    private func enabledBinding(for moduleID: ModuleID) -> Binding<Bool> {
        Binding(
            get: { moduleStore.isEnabled(moduleID) },
            set: { moduleStore.setEnabled($0, for: moduleID) }
        )
    }
}
