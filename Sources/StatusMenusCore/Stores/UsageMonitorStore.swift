import Combine
import Foundation

@MainActor
public final class UsageMonitorStore: ObservableObject {
    @Published public var snapshot: UsageSnapshot?
    @Published public var isRefreshing = false

    private let usageService: UsageService
    private var refreshTask: Task<Void, Never>?
    private var refreshConfiguration: Double?

    public init(usageService: UsageService = UsageService()) {
        self.usageService = usageService
    }

    deinit {
        refreshTask?.cancel()
    }

    public func startRefreshLoop(refreshInterval: Double) {
        let effectiveInterval = max(ModuleStore.minimumRefreshInterval, refreshInterval)
        guard refreshConfiguration != effectiveInterval else {
            return
        }

        refreshTask?.cancel()
        refreshConfiguration = effectiveInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    break
                }

                await self.refreshNow()

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

    public func refreshNow() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let usageService = usageService
        let nextSnapshot = await Task.detached(priority: .utility) {
            usageService.snapshot()
        }.value
        snapshot = nextSnapshot
        isRefreshing = false
    }
}
