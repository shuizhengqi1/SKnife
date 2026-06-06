import StatusMenusCore
import SwiftUI

struct UsageMonitorView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @State private var snapshot: UsageSnapshot?
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Usage Monitor",
                    subtitle: "Local process, CPU, and memory overview",
                    symbolName: "chart.bar"
                )

                HStack {
                    MetricTile(
                        title: "Physical Memory",
                        value: snapshot.map { StatusFormatters.bytes(Int64(clamping: $0.memoryTotalBytes)) } ?? "Not loaded",
                        subtitle: "Installed RAM",
                        symbolName: "memorychip"
                    )
                    MetricTile(
                        title: "Top CPU Rows",
                        value: snapshot.map { "\($0.topCPUProcesses.count)" } ?? "0",
                        subtitle: "From ps snapshot",
                        symbolName: "cpu"
                    )
                    MetricTile(
                        title: "Captured",
                        value: StatusFormatters.shortDateTime(snapshot?.capturedAt),
                        subtitle: "Last refresh",
                        symbolName: "clock"
                    )
                }

                HStack {
                    Text("Top processes")
                        .font(.headline)
                    Spacer()
                    Button {
                        refresh()
                    } label: {
                        HStack(spacing: 6) {
                            SymbolIcon(symbolName: "arrow.clockwise", size: 14)
                            Text(isRefreshing ? "Refreshing" : "Refresh")
                        }
                    }
                    .disabled(isRefreshing)
                }

                if let snapshot {
                    processTable(title: "CPU", processes: snapshot.topCPUProcesses, value: { String(format: "%.1f%%", $0.cpuPercent) })
                    processTable(title: "Memory", processes: snapshot.topMemoryProcesses, value: { String(format: "%.1f%%", $0.memoryPercent) })
                } else {
                    EmptyStateView(
                        title: "Usage snapshot not loaded",
                        message: "Press Refresh to capture a local process snapshot.",
                        symbolName: "chart.bar"
                    )
                }
            }
            .padding(24)
        }
        .task(id: moduleStore.effectiveRefreshInterval) {
            await refreshLoop()
        }
    }

    private func processTable(title: String, processes: [ProcessSample], value: @escaping (ProcessSample) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(processes) { process in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.displayName)
                        Text("PID \(process.pid) · \(process.elapsed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(value(process))
                        .font(.body.monospacedDigit())
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func refresh() {
        Task {
            await refreshNow()
        }
    }

    @MainActor
    private func refreshLoop() async {
        while !Task.isCancelled {
            await refreshNow()

            do {
                try await Task.sleep(nanoseconds: refreshNanoseconds)
            } catch {
                break
            }
        }
    }

    @MainActor
    private func refreshNow() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let nextSnapshot = await Task.detached(priority: .utility) {
            UsageService().snapshot()
        }.value
        snapshot = nextSnapshot
        isRefreshing = false
    }

    private var refreshNanoseconds: UInt64 {
        UInt64(moduleStore.effectiveRefreshInterval * 1_000_000_000)
    }
}
