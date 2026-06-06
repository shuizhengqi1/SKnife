import StatusMenusCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @Binding var selection: ModuleID?

    var body: some View {
        List(selection: $selection) {
            Section("Functions") {
                ForEach(moduleStore.enabledDescriptors) { module in
                    SidebarRow(module: module)
                        .tag(module.id as ModuleID?)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRow: View {
    let module: ModuleDescriptor

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.body)
                Text(module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            SymbolIcon(symbolName: module.symbolName, size: 16)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
