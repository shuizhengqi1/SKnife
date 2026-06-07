import AppKit
import StatusMenusCore
import SwiftUI

struct SlockAgentsView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @EnvironmentObject private var slockStore: SlockMonitorStore
    @State private var editingAgent: EditableSlockAgent?
    @State private var saveErrorMessage: String?
    @State private var isSavingMemory = false

    private var snapshot: SlockSnapshot? { slockStore.snapshot }
    private var errorMessage: String? { slockStore.errorMessage }
    private var isRefreshing: Bool { slockStore.isRefreshing }
    private var metricHistory: [SlockMetricSample] { slockStore.metricHistory }
    private var costSummaries: [SlockAgentCostSummary] { slockStore.costSummaries }

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
                        MetricTile(title: "LLM Cost", value: costUSD(totalLLMCost), subtitle: "\(totalUsageEvents) local token events", symbolName: "dollarsign.circle")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    metricHistorySection
                    costTelemetrySection
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
        .sheet(item: $editingAgent) { draft in
            SlockMemoryEditorSheet(
                initialDraft: draft,
                saveErrorMessage: $saveErrorMessage,
                isSaving: isSavingMemory,
                onCancel: {
                    saveErrorMessage = nil
                    editingAgent = nil
                },
                onSave: { draft in
                    saveMemoryDraft(draft)
                }
            )
        }
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
                                agentCostLine(for: agent)
                            }
                            Spacer()
                            Text(StatusFormatters.bytes(agent.byteCount))
                                .font(.body.monospacedDigit())
                            Button {
                                saveErrorMessage = nil
                                editingAgent = EditableSlockAgent(agent: agent)
                            } label: {
                                SymbolIcon(symbolName: "pencil", size: 14)
                            }
                            .buttonStyle(.borderless)
                            .help("Edit MEMORY.md")
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
    private func agentCostLine(for agent: SlockAgentWorkspace) -> some View {
        if let summary = costSummary(for: agent) {
            HStack(spacing: 8) {
                Label(costUSD(summary.totalCostUSD), systemImage: "dollarsign.circle")
                Text("\(tokenCount(summary.totalTokens)) tokens")
                Text("\(summary.eventCount) events")
                if !summary.modelNames.isEmpty {
                    Text(summary.modelNames.joined(separator: ", "))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text("No local LLM cost telemetry")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            await slockStore.refreshNow(rootPath: moduleStore.slockRootPath)
        }
    }

    private func saveMemoryDraft(_ draft: EditableSlockAgent) {
        Task {
            await saveMemoryDraftOnMain(draft)
        }
    }

    @MainActor
    private func saveMemoryDraftOnMain(_ draft: EditableSlockAgent) async {
        guard !isSavingMemory else {
            return
        }

        isSavingMemory = true
        saveErrorMessage = nil
        defer {
            isSavingMemory = false
        }

        let agentURL = draft.url
        let memoryDraft = draft.memoryDraft
        do {
            try await slockStore.saveMemoryDraft(agentURL: agentURL, draft: memoryDraft)
            editingAgent = nil
            saveErrorMessage = nil
        } catch {
            let message = "Could not save MEMORY.md: \(error.localizedDescription)"
            saveErrorMessage = message
            slockStore.errorMessage = message
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var costTelemetrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LLM cost telemetry")
                    .font(.headline)
                Spacer()
                Text("\(costSummaries.count) agents · \(totalUsageEvents) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                MetricTile(title: "Total Cost", value: costUSD(totalLLMCost), subtitle: "Slock-reported USD", symbolName: "dollarsign.circle")
                MetricTile(title: "Usage Events", value: "\(totalUsageEvents)", subtitle: "Token snapshots", symbolName: "bolt.horizontal.circle")
                MetricTile(title: "Input Tokens", value: tokenCount(totalInputTokens), subtitle: "Prompt + model input", symbolName: "arrow.down.circle")
                MetricTile(title: "Output Tokens", value: tokenCount(totalOutputTokens), subtitle: "Completion output", symbolName: "arrow.up.circle")
            }

            if costSummaries.isEmpty {
                EmptyStateView(
                    title: "No local LLM cost telemetry",
                    message: "Slock agent folders are visible, but the local daemon traces have not emitted token usage or cost events yet.",
                    symbolName: "waveform.path.ecg"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(costSummaries) { summary in
                        costSummaryRow(summary)
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func costSummaryRow(_ summary: SlockAgentCostSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolIcon(symbolName: "dollarsign.circle", size: 18)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(agentName(for: summary.agentID))
                    .font(.subheadline.weight(.semibold))
                Text(summary.agentID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("\(tokenCount(summary.inputTokens)) in")
                    Text("\(tokenCount(summary.outputTokens)) out")
                    Text("\(tokenCount(summary.cachedInputTokens)) cached")
                    Text("\(summary.eventCount) events")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !summary.modelNames.isEmpty {
                    Text(summary.modelNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(costUSD(summary.totalCostUSD))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(StatusFormatters.shortDateTime(summary.lastUsageAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var metricHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Metric history")
                    .font(.headline)
                Spacer()
                Text("\(metricHistory.count) samples · refresh \(Int(moduleStore.effectiveRefreshInterval))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                slockMetricCard(
                    title: "Agents",
                    value: latest.map { "\($0.agentCount)" } ?? "-",
                    subtitle: "workspace count",
                    values: metricHistory.map { Double($0.agentCount) },
                    color: .blue,
                    symbolName: "folder"
                )
                slockMetricCard(
                    title: "Processes",
                    value: latest.map { "\($0.processCount)" } ?? "-",
                    subtitle: "Slock-related",
                    values: metricHistory.map { Double($0.processCount) },
                    color: .purple,
                    symbolName: "cpu"
                )
                slockMetricCard(
                    title: "Agent CPU",
                    value: latest.map { String(format: "%.1f%%", $0.agentCPUPercent) } ?? "-",
                    subtitle: "combined process CPU",
                    values: metricHistory.map(\.agentCPUPercent),
                    color: .orange,
                    symbolName: "speedometer"
                )
                slockMetricCard(
                    title: "Agent MEM",
                    value: latest.map { String(format: "%.1f%%", $0.agentMemoryPercent) } ?? "-",
                    subtitle: "combined process memory",
                    values: metricHistory.map(\.agentMemoryPercent),
                    color: .green,
                    symbolName: "memorychip"
                )
                slockMetricCard(
                    title: "Agent Disk",
                    value: latest.map { StatusFormatters.bytes($0.agentDiskBytes) } ?? "-",
                    subtitle: "workspace storage",
                    values: metricHistory.map { Double($0.agentDiskBytes) },
                    color: .cyan,
                    symbolName: "internaldrive"
                )
                slockMetricCard(
                    title: "Machines",
                    value: latest.map { "\($0.machineCount)" } ?? "-",
                    subtitle: "machine records",
                    values: metricHistory.map { Double($0.machineCount) },
                    color: .indigo,
                    symbolName: "desktopcomputer"
                )
                slockMetricCard(
                    title: "Traces",
                    value: latest.map { "\($0.traceCount)" } ?? "-",
                    subtitle: "trace files",
                    values: metricHistory.map { Double($0.traceCount) },
                    color: .pink,
                    symbolName: "waveform.path.ecg"
                )
            }
        }
    }

    private var latest: SlockMetricSample? {
        metricHistory.last
    }

    private var totalLLMCost: Double {
        costSummaries.reduce(0) { $0 + $1.totalCostUSD }
    }

    private var totalUsageEvents: Int {
        costSummaries.reduce(0) { $0 + $1.eventCount }
    }

    private var totalInputTokens: Int {
        costSummaries.reduce(0) { $0 + $1.inputTokens }
    }

    private var totalOutputTokens: Int {
        costSummaries.reduce(0) { $0 + $1.outputTokens }
    }

    private func costSummary(for agent: SlockAgentWorkspace) -> SlockAgentCostSummary? {
        costSummaries.first { $0.agentID == agent.id }
    }

    private func agentName(for agentID: String) -> String {
        snapshot?.agents.first { $0.id == agentID }?.displayName ?? agentID
    }

    private func costUSD(_ value: Double) -> String {
        if abs(value) < 0.0001 {
            return "$0.00"
        }
        return value >= 100 ? String(format: "$%.2f", value) : String(format: "$%.4f", value)
    }

    private func tokenCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func slockMetricCard(
        title: String,
        value: String,
        subtitle: String,
        values: [Double],
        color: Color,
        symbolName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SymbolIcon(symbolName: symbolName, size: 16)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            SlockSparklineView(values: values, color: color)
                .frame(height: 42)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.22))
        )
    }
}

private struct SlockSparklineView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.08))

                Path { path in
                    let points = normalizedPoints(in: proxy.size)
                    guard let first = points.first else {
                        return
                    }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if values.count < 2 {
                    Text("waiting")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel("Metric sparkline")
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty, size.width > 0, size.height > 0 else {
            return []
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = max(1, maxValue - minValue)
        let xStep = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            let x = CGFloat(index) * xStep
            let normalized = (value - minValue) / range
            let y = size.height - CGFloat(normalized) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

private struct EditableSlockAgent: Identifiable, Equatable {
    let id: String
    let url: URL
    var displayName: String
    var description: String
    var memorySections: [EditableMemorySection]

    init(agent: SlockAgentWorkspace) {
        id = agent.url.path
        url = agent.url
        displayName = agent.displayName
        description = agent.description ?? ""
        memorySections = agent.memorySections.map {
            EditableMemorySection(title: $0.title, body: $0.body)
        }
    }

    var memoryFileURL: URL {
        url.appendingPathComponent("MEMORY.md")
    }

    var memoryDraft: SlockAgentMemoryDraft {
        SlockAgentMemoryDraft(
            displayName: displayName,
            description: description,
            memorySections: memorySections.map {
                SlockAgentMemorySection(title: $0.title, body: $0.body)
            }
        )
    }
}

private struct EditableMemorySection: Identifiable, Equatable {
    let id: UUID
    var title: String
    var body: String

    init(id: UUID = UUID(), title: String = "", body: String = "") {
        self.id = id
        self.title = title
        self.body = body
    }
}

private struct SlockMemoryEditorSheet: View {
    @State private var draft: EditableSlockAgent
    @Binding var saveErrorMessage: String?

    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: (EditableSlockAgent) -> Void

    init(
        initialDraft: EditableSlockAgent,
        saveErrorMessage: Binding<String?>,
        isSaving: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (EditableSlockAgent) -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        _saveErrorMessage = saveErrorMessage
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit MEMORY.md")
                    .font(.title2.weight(.semibold))
                Text(draft.memoryFileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Form {
                Section("Profile") {
                    TextField("Name", text: $draft.displayName)
                        .disabled(true)
                        .help("Slock agent names are managed by Slock and are read-only here.")
                    Text("Agent names are managed by Slock. Local edits only update description and memory sections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $draft.description)
                            .font(.body)
                            .frame(minHeight: 76)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(.quaternary)
                            )
                    }
                }

                Section("Memory Sections") {
                    if draft.memorySections.isEmpty {
                        Text("No memory sections.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($draft.memorySections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Section title", text: section.title)
                                Button {
                                    removeSection(section.wrappedValue.id)
                                } label: {
                                    SymbolIcon(symbolName: "trash", size: 14)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove section")
                            }

                            TextEditor(text: section.body)
                                .font(.body)
                                .frame(minHeight: 92)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(.quaternary)
                                )
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        addSection()
                    } label: {
                        HStack(spacing: 6) {
                            SymbolIcon(symbolName: "plus", size: 14)
                            Text("Add Section")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider()
            HStack {
                Button {
                    NSWorkspace.shared.open(draft.url)
                } label: {
                    HStack(spacing: 6) {
                        SymbolIcon(symbolName: "folder", size: 14)
                        Text("Open Folder")
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Button(isSaving ? "Saving" : "Save") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
            .padding(20)
        }
        .frame(width: 620)
        .frame(minHeight: 580)
    }

    private func addSection() {
        draft.memorySections.append(EditableMemorySection(title: "New Section"))
    }

    private func removeSection(_ id: UUID) {
        draft.memorySections.removeAll { $0.id == id }
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
