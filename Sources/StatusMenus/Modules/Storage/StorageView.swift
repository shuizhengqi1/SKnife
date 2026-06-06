import StatusMenusCore
import SwiftUI

struct StorageView: View {
    @State private var snapshot = StorageSnapshot.empty
    @State private var isScanning = false

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
                        value: diskValue(StatusFormatters.bytes(snapshot.disk.used)),
                        subtitle: snapshot.disk.capacity > 0 ? StatusFormatters.wholePercent(snapshot.disk.usedFraction) : "Loading",
                        symbolName: "chart.pie"
                    )
                    MetricTile(
                        title: "Available",
                        value: diskValue(StatusFormatters.bytes(snapshot.disk.available)),
                        subtitle: "Free for important usage",
                        symbolName: "checkmark.seal"
                    )
                    MetricTile(
                        title: "Capacity",
                        value: diskValue(StatusFormatters.bytes(snapshot.disk.capacity)),
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
                            scanFolderSizes()
                        } label: {
                            HStack(spacing: 6) {
                                SymbolIcon(symbolName: "arrow.clockwise", size: 14)
                                Text(isScanning ? "Scanning" : "Scan sizes")
                            }
                        }
                        .disabled(isScanning)
                    }

                    if snapshot.folders.isEmpty {
                        EmptyStateView(
                            title: "Storage scan not started",
                            message: "Press Scan sizes to calculate disk summary and folder candidates in the background.",
                            symbolName: "internaldrive"
                        )
                    } else {
                        ForEach(snapshot.folders) { folder in
                            HStack(spacing: 12) {
                                SymbolIcon(symbolName: folder.isCleanupCandidate ? "sparkles" : "folder", size: 16)
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
                                Text(folder.byteCount.map(StatusFormatters.bytes) ?? "Not scanned")
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
            }
            .padding(24)
        }
    }

    private func diskValue(_ formattedValue: String) -> String {
        snapshot.disk.capacity > 0 ? formattedValue : "Loading"
    }

    private func scanFolderSizes() {
        guard !isScanning else {
            return
        }

        isScanning = true
        Task {
            let nextSnapshot = await Task.detached(priority: .utility) {
                StorageService().snapshot(includeFolderSizes: true, includeDiskCapacity: true)
            }.value
            snapshot = nextSnapshot
            isScanning = false
        }
    }
}
