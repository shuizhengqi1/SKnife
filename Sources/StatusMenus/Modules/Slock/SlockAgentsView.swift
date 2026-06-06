import AppKit
import StatusMenusCore
import SwiftUI

struct SlockAgentsView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @State private var snapshot: SlockSnapshot?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Slock Agents",
                    subtitle: "Auto-detected local Slock daemon state, agents, machines, and traces",
                    symbolName: "person.2"
                )

                if let snapshot {
                    HStack {
                        StatusBadge(status: snapshot.status)
                        Text(snapshot.rootURL.path)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        MetricTile(title: "Agents", value: "\(snapshot.agents.count)", subtitle: "Workspaces", symbolName: "folder")
                        MetricTile(title: "Machines", value: "\(snapshot.machines.count)", subtitle: "Local machine records", symbolName: "desktopcomputer")
                        MetricTile(title: "Processes", value: "\(snapshot.processes.count)", subtitle: "Command redacted", symbolName: "cpu")
                    }

                    agentSection(snapshot.agents)
                    machineSection(snapshot.machines)
                    processSection(snapshot.processes)
                } else {
                    EmptyStateView(
                        title: "No Slock snapshot",
                        message: errorMessage ?? "Refresh to scan the configured Slock root.",
                        symbolName: "magnifyingglass"
                    )
                    Button {
                        refresh()
                    } label: {
                        HStack(spacing: 6) {
                            SymbolIcon(symbolName: "arrow.clockwise", size: 14)
                            Text(isRefreshing ? "Scanning" : "Scan Slock")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .padding(24)
        }
        .task(id: refreshLoopID) {
            await refreshLoop()
        }
    }

    private var refreshLoopID: String {
        "\(moduleStore.slockRootPath)|\(moduleStore.effectiveRefreshInterval)"
    }

    @ViewBuilder
    private func agentSection(_ agents: [SlockAgentWorkspace]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent workspaces")
                .font(.headline)
            if agents.isEmpty {
                EmptyStateView(
                    title: "No agents found",
                    message: "The app scans every directory under the configured Slock agents folder.",
                    symbolName: "folder"
                )
            } else {
                ForEach(agents) { agent in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            AgentAvatarView(agent: agent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(agent.displayName)
                                    .font(.headline)
                                Text(agent.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if let description = agent.description {
                                    Text(description)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(agent.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(StatusFormatters.bytes(agent.byteCount))
                                .font(.body.monospacedDigit())
                            Button {
                                NSWorkspace.shared.open(agent.url)
                            } label: {
                                SymbolIcon(symbolName: "arrow.up.right.square", size: 14)
                            }
                            .buttonStyle(.borderless)
                            .help("Open workspace")
                            Button {
                                copy(agent.url.path)
                            } label: {
                                SymbolIcon(symbolName: "doc.on.doc", size: 14)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy path")
                        }

                        if !agent.memorySections.isEmpty {
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(agent.memorySections) { section in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(section.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(section.body)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("Memory")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.leading, 48)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func machineSection(_ machines: [SlockMachine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Machines")
                .font(.headline)
            if machines.isEmpty {
                Text("No machine records found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(machines) { machine in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.id)
                                .font(.body.monospaced())
                            Text("Traces: \(machine.traceCount) · Lock owner: \(machine.hasLockOwner ? "yes" : "no") · Latest: \(StatusFormatters.shortDateTime(machine.latestTraceModifiedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(machine.url)
                        } label: {
                            SymbolIcon(symbolName: "arrow.up.right.square", size: 14)
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal machine folder")
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func processSection(_ processes: [ProcessSample]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Processes")
                .font(.headline)
            if processes.isEmpty {
                Text("No active Slock-related processes were found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(process.displayName)
                            Text("PID \(process.pid) · running \(process.elapsed) · command redacted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f%% CPU", process.cpuPercent))
                            .font(.body.monospacedDigit())
                        Text(String(format: "%.1f%% MEM", process.memoryPercent))
                            .font(.body.monospacedDigit())
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
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

        let root = URL(fileURLWithPath: NSString(string: moduleStore.slockRootPath).expandingTildeInPath)
        isRefreshing = true
        do {
            let nextSnapshot = try await Task.detached(priority: .utility) {
                try SlockDiscoveryService().liveSnapshot(rootURL: root)
            }.value
            snapshot = nextSnapshot
            errorMessage = nil
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    private var refreshNanoseconds: UInt64 {
        UInt64(moduleStore.effectiveRefreshInterval * 1_000_000_000)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct AgentAvatarView: View {
    let agent: SlockAgentWorkspace

    var body: some View {
        Group {
            if let avatarURL = agent.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.16))
            Text(initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var initials: String {
        let parts = agent.displayName
            .split { !$0.isLetter && !$0.isNumber }
        let letters = parts
            .prefix(2)
            .compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? String(agent.id.prefix(2)).uppercased() : value
    }
}
