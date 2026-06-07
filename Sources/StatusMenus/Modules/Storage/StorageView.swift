import AppKit
import StatusMenusCore
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var storageStore: StorageMonitorStore

    private let panelStroke = Color.secondary.opacity(0.18)

    private var analysis: StorageAnalysis { storageStore.analysis }
    private var isScanning: Bool { storageStore.isScanning }
    private var scanProgress: StorageScanProgress? { storageStore.scanProgress }
    private var rootPath: String { storageStore.rootPath }
    private var scanMode: StorageScanMode { storageStore.scanMode }
    private var selectedNode: StorageNode? { storageStore.selectedNode }
    private var selectedCandidateIDs: Set<String> { storageStore.selectedCandidateIDs }
    private var cleanupMessage: String? { storageStore.cleanupMessage }
    private var indexMessage: String? { storageStore.indexMessage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Storage",
                    subtitle: "Technical space topology, ranked paths, and Trash-based cleanup review",
                    symbolName: "internaldrive"
                )

                scanControls
                operationsDeck
                rankedPaths
            }
            .padding(24)
        }
    }

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Scan path", text: $storageStore.rootPath)
                    .textFieldStyle(.roundedBorder)
                Picker("Scan mode", selection: $storageStore.scanMode) {
                    ForEach(StorageScanMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Button {
                    scan()
                } label: {
                    HStack(spacing: 6) {
                        SymbolIcon(symbolName: "arrow.clockwise", size: 14)
                        Text(isScanning ? "Scanning" : "Scan")
                    }
                }
                .disabled(isScanning)
                .keyboardShortcut("r")
            }

            HStack(spacing: 8) {
                quickPathButton("Home", FileManager.default.homeDirectoryForCurrentUser)
                quickPathButton("Caches", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"))
                quickPathButton("Developer", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer"))
                quickPathButton("Slock", SlockDiscoveryService.defaultRootURL)
                Spacer()
                Text(isScanning ? "Scanning \(scanMode.label.lowercased()) profile" : scanMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            scanStatus

            DisclosureGroup(isExpanded: $storageStore.showAdvanced) {
                Stepper("Custom scan reach \(storageStore.customDepth)", value: $storageStore.customDepth, in: 1...8)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } label: {
                Text("Advanced")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var operationsDeck: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                technicalMetric("Used", StatusFormatters.bytes(analysis.disk.used), symbolName: "chart.pie", color: .blue)
                technicalMetric("Tree Size", StatusFormatters.bytes(analysis.root.byteCount), symbolName: "point.3.connected.trianglepath.dotted", color: .cyan)
                technicalMetric("Progress", scanProgressMetricLabel, symbolName: "percent", color: .indigo)
                technicalMetric("Scan Time", scanTimeMetricLabel, symbolName: "timer", color: .purple)
                technicalMetric("Indexed", "\(analysis.indexedFileCount)", symbolName: "number", color: .green)
                technicalMetric("Clean Plan", StatusFormatters.bytes(selectedCleanupBytes), symbolName: "trash", color: .orange)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    scanMatrix
                        .frame(width: 220)
                    topologyPanel
                        .frame(minWidth: 460)
                    cleanupReview
                        .frame(width: 270)
                }

                VStack(alignment: .leading, spacing: 14) {
                    scanMatrix
                        .frame(maxWidth: .infinity)
                    topologyPanel
                        .frame(maxWidth: .infinity)
                    cleanupReview
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(panelStroke)
        )
    }

    private var topologyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Treemap / Size Topology")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Click a block to inspect the path. Use Deep scan for a fuller tree.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(rootDisplayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            StorageTreemapView(
                nodes: Array(analysis.rankedNodes.prefix(14)),
                selectedNodeID: selectedNode?.id
            ) { node in
                storageStore.selectedNode = node
            }
            .frame(height: 300)

            selectedNodeDetails
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(panelStroke)
        )
    }

    private var scanMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest Folders")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if analysis.root.children.isEmpty {
                    Text("Run a scan to see the largest folders in this location.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }

                ForEach(Array(analysis.root.children.prefix(8))) { node in
                    Button {
                        storageStore.selectedNode = node
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(node.risk.rawValue)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(color(for: node.risk))
                            }
                            Spacer()
                            Text(StatusFormatters.bytes(node.byteCount))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(9)
                        .background(color(for: node.risk).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(color(for: node.risk).opacity(0.28))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(analysis.scanLog, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if analysis.scanLog.isEmpty {
                    Text("Ready to analyze \(rootDisplayPath).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let indexMessage {
                    Text(indexMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(panelStroke)
        )
    }

    private var selectedNodeDetails: some View {
        HStack(spacing: 10) {
            if let selectedNode {
                SymbolIcon(symbolName: selectedNode.isDirectory ? "folder" : "doc", size: 16)
                    .foregroundStyle(color(for: selectedNode.risk))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedNode.url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(StatusFormatters.bytes(selectedNode.byteCount)) · \(selectedNode.risk.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([selectedNode.url])
                }
            } else {
                Text("No block selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cleanupReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Review")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(StatusFormatters.bytes(selectedCleanupBytes))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("selected reclaim preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if analysis.cleanupCandidates.isEmpty {
                Text("No cleanup candidates found for this scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(analysis.cleanupCandidates.prefix(10))) { candidate in
                        Toggle(isOn: candidateBinding(candidate)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(candidate.risk.rawValue) · \(StatusFormatters.bytes(candidate.byteCount))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(color(for: candidate.risk))
                                Text(candidate.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            if let cleanupMessage {
                Text(cleanupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                moveSelectedCandidatesToTrash()
            } label: {
                HStack {
                    SymbolIcon(symbolName: "trash", size: 14)
                    Text("Move to Trash")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedCandidateIDs.isEmpty || isScanning)

            Button {
                revealSelectedCleanup()
            } label: {
                HStack {
                    SymbolIcon(symbolName: "folder", size: 14)
                    Text("Reveal Selection")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedCandidateIDs.isEmpty)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(panelStroke)
        )
    }

    private var rankedPaths: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ranked Paths")
                    .font(.headline)
                Spacer()
                Text("\(analysis.rankedNodes.count) indexed nodes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if analysis.rankedNodes.isEmpty {
                EmptyStateView(
                    title: "Storage scan not started",
                    message: "Choose a path and press Scan to build the treemap and cleanup plan.",
                    symbolName: "internaldrive"
                )
            } else {
                ForEach(Array(analysis.rankedNodes.prefix(80))) { node in
                    HStack(spacing: 12) {
                        SymbolIcon(symbolName: node.isDirectory ? "folder" : "doc", size: 16)
                            .foregroundStyle(color(for: node.risk))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title)
                            Text(node.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(node.risk.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: node.risk))
                        Text(StatusFormatters.bytes(node.byteCount))
                            .font(.body.monospacedDigit())
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        storageStore.selectedNode = node
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    private var rootDisplayPath: String {
        rootPath.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private var selectedCleanupCandidates: [StorageCleanupCandidate] {
        storageStore.selectedCleanupCandidates
    }

    private var selectedCleanupBytes: Int64 {
        storageStore.selectedCleanupBytes
    }

    private var effectiveScanDepth: Int {
        storageStore.effectiveScanDepth
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 128), spacing: 12)]
    }

    @ViewBuilder
    private var scanStatus: some View {
        if isScanning, let scanProgress {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    if let percent = scanProgress.percentComplete {
                        ProgressView(value: percent)
                            .frame(maxWidth: 260)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(scanProgressHeadline)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Time \(StatusFormatters.duration(scanProgress.elapsedSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let currentPath = scanProgress.currentPath {
                    Text(currentPath.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if analysis.scanFinishedAt != nil || indexMessage != nil {
            HStack(spacing: 8) {
                SymbolIcon(symbolName: "checkmark.circle", size: 14)
                    .foregroundStyle(.green)
                Text(scanCompleteSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(9)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var scanProgressHeadline: String {
        guard let scanProgress else {
            return "Ready"
        }
        switch scanProgress.phase {
        case .preparing:
            return "Counting scan work"
        case .scanning:
            if let percent = scanProgress.percentComplete {
                return "Scanning \(StatusFormatters.wholePercent(percent))"
            }
            return "Scanning"
        case .indexing:
            return "Writing local index"
        case .finished:
            return "Scan complete"
        }
    }

    private var scanCompleteSummary: String {
        let finished = StatusFormatters.shortDateTime(analysis.scanFinishedAt)
        let duration = StatusFormatters.duration(analysis.scanDuration)
        if let indexMessage {
            return "\(indexMessage) · Last scan \(finished) · \(duration)"
        }
        return "Last scan \(finished) · \(duration)"
    }

    private var scanProgressMetricLabel: String {
        if isScanning, let percent = scanProgress?.percentComplete {
            return StatusFormatters.wholePercent(percent)
        }
        if analysis.scanFinishedAt != nil {
            return "100%"
        }
        return "--"
    }

    private var scanTimeMetricLabel: String {
        if isScanning, let elapsedSeconds = scanProgress?.elapsedSeconds {
            return StatusFormatters.duration(elapsedSeconds)
        }
        guard analysis.scanFinishedAt != nil else {
            return "--"
        }
        return StatusFormatters.duration(analysis.scanDuration)
    }

    private func technicalMetric(_ title: String, _ value: String, symbolName: String, color: Color) -> some View {
        HStack(spacing: 10) {
            SymbolIcon(symbolName: symbolName, size: 20)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.24))
        )
    }

    private func quickPathButton(_ title: String, _ url: URL) -> some View {
        Button(title) {
            storageStore.rootPath = url.path
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func candidateBinding(_ candidate: StorageCleanupCandidate) -> Binding<Bool> {
        Binding {
            storageStore.selectedCandidateIDs.contains(candidate.id)
        } set: { isSelected in
            storageStore.setCandidateSelected(candidate, isSelected: isSelected)
        }
    }

    private func scan(clearCleanupMessage: Bool = true) {
        Task {
            await storageStore.scan(clearCleanupMessage: clearCleanupMessage)
        }
    }

    private func moveSelectedCandidatesToTrash() {
        Task {
            await storageStore.moveSelectedCandidatesToTrash()
        }
    }

    private func revealSelectedCleanup() {
        let urls = selectedCleanupCandidates.map(\.url)
        guard !urls.isEmpty else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func color(for risk: StorageCleanupRisk) -> Color {
        switch risk {
        case .safe:
            return .green
        case .review:
            return .orange
        case .protected:
            return .blue
        }
    }
}

private struct StorageTreemapView: View {
    let nodes: [StorageNode]
    let selectedNodeID: String?
    let onSelect: (StorageNode) -> Void

    var body: some View {
        GeometryReader { proxy in
            let tiles = treemapTiles(in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                if tiles.isEmpty {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                    Text("No scan data")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(tiles) { tile in
                        Button {
                            onSelect(tile.node)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tile.node.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(StatusFormatters.bytes(tile.node.byteCount))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.78))
                                Spacer(minLength: 0)
                                Text(tile.node.risk.rawValue)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .padding(10)
                            .frame(width: tile.rect.width, height: tile.rect.height, alignment: .topLeading)
                            .background(tile.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(tile.node.id == selectedNodeID ? .white : .white.opacity(0.16), lineWidth: tile.node.id == selectedNodeID ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                    }
                }
            }
        }
    }

    private func treemapTiles(in rect: CGRect) -> [TreemapTile] {
        let visibleNodes = nodes.filter { $0.byteCount > 0 }
        guard !visibleNodes.isEmpty else {
            return []
        }

        var remainingRect = rect
        var remainingTotal = CGFloat(visibleNodes.reduce(Int64(0)) { $0 + $1.byteCount })
        var tiles: [TreemapTile] = []

        for (index, node) in visibleNodes.enumerated() {
            let tileRect: CGRect
            if index == visibleNodes.count - 1 || remainingTotal <= 0 {
                tileRect = remainingRect
            } else {
                let fraction = CGFloat(node.byteCount) / remainingTotal
                if remainingRect.width >= remainingRect.height {
                    let width = max(56, min(remainingRect.width, remainingRect.width * fraction))
                    tileRect = CGRect(x: remainingRect.minX, y: remainingRect.minY, width: width, height: remainingRect.height)
                    remainingRect.origin.x += width
                    remainingRect.size.width = max(0, remainingRect.width - width)
                } else {
                    let height = max(48, min(remainingRect.height, remainingRect.height * fraction))
                    tileRect = CGRect(x: remainingRect.minX, y: remainingRect.minY, width: remainingRect.width, height: height)
                    remainingRect.origin.y += height
                    remainingRect.size.height = max(0, remainingRect.height - height)
                }
                remainingTotal -= CGFloat(node.byteCount)
            }

            guard tileRect.width > 4, tileRect.height > 4 else {
                continue
            }
            tiles.append(TreemapTile(node: node, rect: tileRect.insetBy(dx: 3, dy: 3), color: color(for: node, index: index)))
        }
        return tiles
    }

    private func color(for node: StorageNode, index: Int) -> Color {
        if node.risk == .safe {
            return Color(red: 0.05, green: 0.58, blue: 0.52)
        }
        if node.risk == .review {
            return Color(red: 0.86, green: 0.52, blue: 0.08)
        }
        let palette = [
            Color(red: 0.15, green: 0.39, blue: 0.92),
            Color(red: 0.47, green: 0.23, blue: 0.84),
            Color(red: 0.70, green: 0.13, blue: 0.30),
            Color(red: 0.20, green: 0.28, blue: 0.42)
        ]
        return palette[index % palette.count]
    }
}

private struct TreemapTile: Identifiable {
    var id: String { node.id }
    let node: StorageNode
    let rect: CGRect
    let color: Color
}
