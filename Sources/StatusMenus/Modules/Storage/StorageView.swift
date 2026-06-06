import StatusMenusCore
import SwiftUI

struct StorageView: View {
    @State private var snapshot = StorageService().snapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Storage",
                    subtitle: "Read-only space analysis with safe cleanup candidates",
                    symbolName: "internaldrive"
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    MetricTile(
                        title: "Used",
                        value: StatusFormatters.bytes(snapshot.disk.used),
                        subtitle: StatusFormatters.wholePercent(snapshot.disk.usedFraction),
                        symbolName: "chart.pie"
                    )
                    MetricTile(
                        title: "Available",
                        value: StatusFormatters.bytes(snapshot.disk.available),
                        subtitle: "Free for important usage",
                        symbolName: "checkmark.seal"
                    )
                    MetricTile(
                        title: "Capacity",
                        value: StatusFormatters.bytes(snapshot.disk.capacity),
                        subtitle: "Main volume",
                        symbolName: "externaldrive"
                    )
                }

                ProgressView(value: snapshot.disk.usedFraction)
                    .progressViewStyle(.linear)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Folder snapshot")
                            .font(.headline)
                        Spacer()
                        Button {
                            snapshot = StorageService().snapshot()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }

                    ForEach(snapshot.folders) { folder in
                        HStack(spacing: 12) {
                            Image(systemName: folder.isCleanupCandidate ? "sparkles" : "folder")
                                .foregroundStyle(folder.isCleanupCandidate ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.title)
                                Text(folder.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(StatusFormatters.bytes(folder.byteCount))
                                .font(.body.monospacedDigit())
                            if folder.isCleanupCandidate {
                                Text("Preview only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .padding(24)
        }
    }
}
