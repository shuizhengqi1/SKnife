import Foundation

public struct SlockMetricSample: Identifiable, Equatable {
    public var id: Date { sampledAt }

    public let sampledAt: Date
    public let agentCount: Int
    public let machineCount: Int
    public let processCount: Int
    public let traceCount: Int
    public let agentDiskBytes: Int64
    public let agentCPUPercent: Double
    public let agentMemoryPercent: Double

    public init(snapshot: SlockSnapshot, sampledAt: Date = Date()) {
        self.sampledAt = sampledAt
        self.agentCount = snapshot.agents.count
        self.machineCount = snapshot.machines.count
        self.processCount = snapshot.processes.count
        self.traceCount = snapshot.machines.reduce(0) { $0 + $1.traceCount }
        self.agentDiskBytes = snapshot.agents.reduce(Int64(0)) { $0 + $1.byteCount }
        self.agentCPUPercent = snapshot.processes.reduce(0) { $0 + $1.cpuPercent }
        self.agentMemoryPercent = snapshot.processes.reduce(0) { $0 + $1.memoryPercent }
    }

    public static func appending(
        _ sample: SlockMetricSample,
        to history: [SlockMetricSample],
        limit: Int = 60
    ) -> [SlockMetricSample] {
        let cappedLimit = max(1, limit)
        let nextHistory = history + [sample]
        return Array(nextHistory.suffix(cappedLimit))
    }
}
