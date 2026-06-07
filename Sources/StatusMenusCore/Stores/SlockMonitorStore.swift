import Combine
import Foundation

@MainActor
public final class SlockMonitorStore: ObservableObject {
    @Published public var snapshot: SlockSnapshot?
    @Published public var errorMessage: String?
    @Published public var isRefreshing = false
    @Published public var metricHistory: [SlockMetricSample] = []
    @Published public var costSummaries: [SlockAgentCostSummary] = []

    private let discoveryService: SlockDiscoveryService
    private let costService: SlockCostService
    private var refreshTask: Task<Void, Never>?
    private var refreshConfiguration: String?
    private var currentRootPath: String

    public init(
        discoveryService: SlockDiscoveryService = SlockDiscoveryService(),
        costService: SlockCostService = SlockCostService(),
        rootPath: String = SlockDiscoveryService.defaultRootURL.path
    ) {
        self.discoveryService = discoveryService
        self.costService = costService
        self.currentRootPath = rootPath
    }

    deinit {
        refreshTask?.cancel()
    }

    public func startRefreshLoop(rootPath: String, refreshInterval: Double) {
        let effectiveInterval = max(ModuleStore.minimumRefreshInterval, refreshInterval)
        let configuration = "\(rootPath)|\(effectiveInterval)"
        guard refreshConfiguration != configuration else {
            return
        }

        refreshTask?.cancel()
        refreshConfiguration = configuration
        currentRootPath = rootPath
        metricHistory.removeAll()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    break
                }

                await self.refreshNow(rootPath: rootPath)

                do {
                    try await Task.sleep(nanoseconds: UInt64(effectiveInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    public func stopRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshConfiguration = nil
    }

    public func refreshNow(rootPath: String? = nil) async {
        guard !isRefreshing else {
            return
        }

        let resolvedRootPath = rootPath ?? currentRootPath
        currentRootPath = resolvedRootPath
        let root = URL(fileURLWithPath: NSString(string: resolvedRootPath).expandingTildeInPath)
        isRefreshing = true
        do {
            let discoveryService = discoveryService
            let costService = costService
            let result = try await Task.detached(priority: .utility) {
                let nextSnapshot = try discoveryService.liveSnapshot(rootURL: root)
                let nextCosts = costService.summaries(rootURL: nextSnapshot.rootURL)
                return (nextSnapshot, nextCosts)
            }.value
            snapshot = result.0
            costSummaries = result.1
            metricHistory = SlockMetricSample.appending(
                SlockMetricSample(snapshot: result.0),
                to: metricHistory,
                limit: 60
            )
            errorMessage = nil
        } catch {
            snapshot = nil
            costSummaries = []
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    public func saveMemoryDraft(agentURL: URL, draft: SlockAgentMemoryDraft) async throws {
        let discoveryService = discoveryService
        try await Task.detached(priority: .utility) {
            try discoveryService.saveMemoryDraft(agentURL: agentURL, draft: draft)
        }.value
        await refreshNow()
    }
}
