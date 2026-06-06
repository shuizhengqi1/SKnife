import StatusMenusCore
import SwiftUI

struct ModuleManagerView: View {
    @EnvironmentObject private var moduleStore: ModuleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Modules",
                    subtitle: "Enable or disable built-in functions",
                    symbolName: "square.grid.2x2"
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(ModuleRegistry.builtIns) { module in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: module.symbolName)
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.title)
                                        .font(.headline)
                                    Text(module.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }

                            Toggle("Enabled", isOn: enabledBinding(for: module.id))
                                .disabled(module.id == .modules)
                        }
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                Text("New functions can be added as built-in modules by creating a module view, service/model files, and registering a descriptor in ModuleRegistry.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func enabledBinding(for moduleID: ModuleID) -> Binding<Bool> {
        Binding(
            get: { moduleStore.isEnabled(moduleID) },
            set: { moduleStore.setEnabled($0, for: moduleID) }
        )
    }
}
