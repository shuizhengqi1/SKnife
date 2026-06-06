import AppKit
import StatusMenusCore
import SwiftUI

struct StorageView: View {
    @State private var analysis = StorageAnalysis.empty
    @State private var isScanning = false
    @State private var rootPath = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var scanDepth = 3
    @State private var selectedNode: StorageNode?
    @State private var selectedCandidateIDs: Set<String> = []
    @State private var cleanupMessage: String?

    private let panelBackground = Color(red: 0.04, green: 0.07, blue: 0.13)
    private let panelStroke = Color.white.opacity(0.13)

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
                TextField("Scan path", text: $rootPath)
                    .textFieldStyle(.roundedBorder)
                Stepper("Depth \(scanDepth)", value: $scanDepth, in: 1...8)
                    .frame(width: 120)
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
                Text(analysis.scanLog.last ?? "Ready")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var operationsDeck: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                technicalMetric("Used", StatusFormatters.bytes(analysis.disk.used), symbolName: "chart.pie", color: .blue)
                technicalMetric("Tree Size", StatusFormatters.bytes(analysis.root.byteCount), symbolName: "point.3.connected.trianglepath.dotted", color: .cyan)
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
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .foregroundStyle(.white)
                    Text("Click a block to inspect the path. Scan deeper for a fuller tree.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Text(rootDisplayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            StorageTreemapView(
                nodes: Array(analysis.rankedNodes.prefix(14)),
                selectedNodeID: selectedNode?.id
            ) { node in
                selectedNode = node
            }
            .frame(height: 300)

            selectedNodeDetails
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(panelStroke)
        )
    }

    private var scanMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan Matrix")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.58))

            VStack(spacing: 8) {
                ForEach(Array(analysis.root.children.prefix(8))) { node in
                    Button {
                        selectedNode = node
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.title)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(node.risk.rawValue)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(color(for: node.risk))
                            }
                            Spacer()
                            Text(StatusFormatters.bytes(node.byteCount))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.72))
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
                .overlay(.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(analysis.scanLog, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.green.opacity(0.9))
                        .lineLimit(1)
                }
                if analysis.scanLog.isEmpty {
                    Text("agentdock storage scan --path \(rootDisplayPath) --depth \(scanDepth)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green.opacity(0.9))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(StatusFormatters.bytes(selectedNode.byteCount)) · \(selectedNode.risk.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([selectedNode.url])
                }
            } else {
                Text("No block selected")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                Spacer()
            }
        }
        .padding(10)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cleanupReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Review")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.58))

            VStack(alignment: .leading, spacing: 2) {
                Text(StatusFormatters.bytes(selectedCleanupBytes))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("selected reclaim preview")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }

            if analysis.cleanupCandidates.isEmpty {
                Text("No cleanup candidates found for this scan.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(analysis.cleanupCandidates.prefix(10))) { candidate in
                        Toggle(isOn: candidateBinding(candidate)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(candidate.risk.rawValue) · \(StatusFormatters.bytes(candidate.byteCount))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(color(for: candidate.risk))
                                Text(candidate.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
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
                    .foregroundStyle(.white.opacity(0.72))
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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        selectedNode = node
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
        analysis.cleanupCandidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    private var selectedCleanupBytes: Int64 {
        selectedCleanupCandidates.reduce(0) { $0 + $1.byteCount }
    }

    private func technicalMetric(_ title: String, _ value: String, symbolName: String, color: Color) -> some View {
        HStack(spacing: 10) {
            SymbolIcon(symbolName: symbolName, size: 20)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.24))
        )
    }

    private func quickPathButton(_ title: String, _ url: URL) -> some View {
        Button(title) {
            rootPath = url.path
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func candidateBinding(_ candidate: StorageCleanupCandidate) -> Binding<Bool> {
        Binding {
            selectedCandidateIDs.contains(candidate.id)
        } set: { isSelected in
            if isSelected {
                selectedCandidateIDs.insert(candidate.id)
            } else {
                selectedCandidateIDs.remove(candidate.id)
            }
        }
    }

    private func scan(clearCleanupMessage: Bool = true) {
        guard !isScanning else {
            return
        }

        isScanning = true
        if clearCleanupMessage {
            cleanupMessage = nil
        }
        let url = URL(fileURLWithPath: NSString(string: rootPath).expandingTildeInPath)
        let depth = scanDepth
        Task {
            let nextAnalysis = await Task.detached(priority: .utility) {
                StorageService().analysis(rootURL: url, maxDepth: depth, includeHidden: false, includeDiskCapacity: true)
            }.value
            analysis = nextAnalysis
            selectedNode = nextAnalysis.rankedNodes.first
            selectedCandidateIDs = Set(nextAnalysis.cleanupCandidates.filter { $0.risk == .safe }.map(\.id))
            isScanning = false
        }
    }

    private func moveSelectedCandidatesToTrash() {
        let candidates = selectedCleanupCandidates
        guard !candidates.isEmpty else {
            return
        }

        isScanning = true
        Task {
            let results = await Task.detached(priority: .utility) {
                StorageService().moveToTrash(candidates)
            }.value
            let succeeded = results.filter(\.succeeded).count
            cleanupMessage = "\(succeeded) of \(results.count) items moved to Trash."
            isScanning = false
            scan(clearCleanupMessage: false)
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
                        .fill(.black.opacity(0.18))
                    Text("No scan data")
                        .foregroundStyle(.white.opacity(0.56))
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
