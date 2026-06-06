import StatusMenusCore
import SwiftUI

struct UsageMonitorView: View {
    @State private var snapshot = UsageService().snapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Usage Monitor",
                    subtitle: "Local process, CPU, and memory overview",
                    symbolName: "chart.line.uptrend.xyaxis"
                )

                HStack {
                    MetricTile(
                        title: "Physical Memory",
                        value: StatusFormatters.bytes(Int64(clamping: snapshot.memoryTotalBytes)),
                        subtitle: "Installed RAM",
                        symbolName: "memorychip"
                    )
                    MetricTile(
                        title: "Top CPU Rows",
                        value: "\(snapshot.topCPUProcesses.count)",
                        subtitle: "From ps snapshot",
                        symbolName: "cpu"
                    )
                    MetricTile(
                        title: "Captured",
                        value: StatusFormatters.shortDateTime(snapshot.capturedAt),
                        subtitle: "Last refresh",
                        symbolName: "clock"
                    )
                }

                HStack {
                    Text("Top processes")
                        .font(.headline)
                    Spacer()
                    Button {
                        snapshot = UsageService().snapshot()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                processTable(title: "CPU", processes: snapshot.topCPUProcesses, value: { String(format: "%.1f%%", $0.cpuPercent) })
                processTable(title: "Memory", processes: snapshot.topMemoryProcesses, value: { String(format: "%.1f%%", $0.memoryPercent) })
            }
            .padding(24)
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
}
