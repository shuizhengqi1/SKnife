import Combine
import Foundation

@MainActor
public final class StorageMonitorStore: ObservableObject {
    @Published public var analysis = StorageAnalysis.empty
    @Published public var isScanning = false
    @Published public var scanProgress: StorageScanProgress?
    @Published public var rootPath: String
    @Published public var scanMode: StorageScanMode = .balanced
    @Published public var showAdvanced = false
    @Published public var customDepth = StorageScanMode.balanced.maxDepth
    @Published public var selectedNode: StorageNode?
    @Published public var selectedCandidateIDs: Set<String> = []
    @Published public var cleanupMessage: String?
    @Published public var indexMessage: String?

    private let makeIndexStore: () throws -> StorageIndexStore
    private var hasLoadedLocalIndex = false

    public init(
        rootPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        makeIndexStore: @escaping () throws -> StorageIndexStore = { try StorageIndexStore() }
    ) {
        self.rootPath = rootPath
        self.makeIndexStore = makeIndexStore
    }

    public var selectedCleanupCandidates: [StorageCleanupCandidate] {
        analysis.cleanupCandidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    public var selectedCleanupBytes: Int64 {
        selectedCleanupCandidates.reduce(0) { $0 + $1.byteCount }
    }

    public var effectiveScanDepth: Int {
        showAdvanced ? customDepth : scanMode.maxDepth
    }

    public func setCandidateSelected(_ candidate: StorageCleanupCandidate, isSelected: Bool) {
        if isSelected {
            selectedCandidateIDs.insert(candidate.id)
        } else {
            selectedCandidateIDs.remove(candidate.id)
        }
    }

    public func scan(clearCleanupMessage: Bool = true) async {
        guard !isScanning else {
            return
        }

        isScanning = true
        scanProgress = StorageScanProgress(
            phase: .preparing,
            processedItemCount: 0,
            totalItemCount: nil,
            currentPath: rootPath,
            elapsedSeconds: 0
        )
        indexMessage = nil
        if clearCleanupMessage {
            cleanupMessage = nil
        }

        let url = URL(fileURLWithPath: NSString(string: rootPath).expandingTildeInPath)
        let depth = effectiveScanDepth
        let makeIndexStore = makeIndexStore
        let progressHandler: @Sendable (StorageScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.scanProgress = progress
            }
        }

        let result = await Task.detached(priority: .utility) { () -> (StorageAnalysis, String?) in
            let nextAnalysis = StorageService().analysis(
                rootURL: url,
                maxDepth: depth,
                includeHidden: false,
                includeDiskCapacity: true,
                progress: progressHandler
            )
            progressHandler(
                StorageScanProgress(
                    phase: .indexing,
                    processedItemCount: 0,
                    totalItemCount: nil,
                    currentPath: StorageIndexStore.defaultDatabaseURL.path,
                    elapsedSeconds: nextAnalysis.scanDuration
                )
            )
            do {
                try makeIndexStore().save(nextAnalysis)
                progressHandler(
                    StorageScanProgress(
                        phase: .finished,
                        processedItemCount: 1,
                        totalItemCount: 1,
                        currentPath: nextAnalysis.root.url.path,
                        elapsedSeconds: nextAnalysis.scanDuration
                    )
                )
                return (nextAnalysis, nil)
            } catch {
                return (nextAnalysis, error.localizedDescription)
            }
        }.value

        applyAnalysis(result.0, updateRootPath: true)
        if let indexError = result.1 {
            indexMessage = "Scan complete, but local index was not saved: \(indexError)"
        } else {
            indexMessage = "Saved local index at \(StatusFormatters.shortDateTime(result.0.scanFinishedAt))"
        }
        isScanning = false
    }

    public func moveSelectedCandidatesToTrash() async {
        let candidates = selectedCleanupCandidates
        guard !candidates.isEmpty, !isScanning else {
            return
        }

        isScanning = true
        let results = await Task.detached(priority: .utility) {
            StorageService().moveToTrash(candidates)
        }.value
        let succeeded = results.filter(\.succeeded).count
        cleanupMessage = "\(succeeded) of \(results.count) items moved to Trash."
        isScanning = false
        await scan(clearCleanupMessage: false)
    }

    public func loadLatestStorageIndexIfNeeded() async {
        guard !hasLoadedLocalIndex else {
            return
        }
        hasLoadedLocalIndex = true

        let makeIndexStore = makeIndexStore
        let restoredAnalysis = await Task.detached(priority: .utility) {
            try? makeIndexStore().latestAnalysis()
        }.value
        guard let restoredAnalysis, analysis == .empty, !isScanning else {
            return
        }

        applyAnalysis(restoredAnalysis, updateRootPath: true)
        indexMessage = "Loaded local index from \(StatusFormatters.shortDateTime(restoredAnalysis.scanFinishedAt))"
    }

    public func applyAnalysis(_ nextAnalysis: StorageAnalysis, updateRootPath: Bool) {
        analysis = nextAnalysis
        if updateRootPath {
            rootPath = nextAnalysis.root.url.path
        }
        selectedNode = nextAnalysis.rankedNodes.first
        selectedCandidateIDs = Set(nextAnalysis.cleanupCandidates.filter { $0.risk == .safe }.map(\.id))
    }
}
