import Foundation

public struct MenuBarStatusSummary: Equatable {
    public let buttonTitle: String
    public let menuLines: [String]

    public init(
        slock: SlockSnapshot?,
        usage: UsageSnapshot?,
        slockCosts: [SlockAgentCostSummary] = []
    ) {
        let status = slock?.status ?? .unavailable
        let agentCount = slock?.agents.count ?? 0
        let agentNames = slock?.agents.map(\.displayName).filter { !$0.isEmpty } ?? []
        let machineCount = slock?.machines.count ?? 0
        let slockProcessCount = slock?.processes.count ?? 0
        let agentCPU = slock?.processes.reduce(0) { $0 + $1.cpuPercent } ?? 0
        let agentMemory = slock?.processes.reduce(0) { $0 + $1.memoryPercent } ?? 0
        let agentDisk = slock?.agents.reduce(Int64(0)) { $0 + $1.byteCount } ?? 0
        let llmCost = slockCosts.reduce(0) { $0 + $1.totalCostUSD }
        let llmEvents = slockCosts.reduce(0) { $0 + $1.eventCount }

        self.buttonTitle = "AgentDock \(agentCount)A"

        var lines = [
            "Slock: \(status.label)",
            "Agents: \(agentCount)",
            "Machines: \(machineCount)",
            "Slock procs: \(slockProcessCount)",
            "LLM cost: \(Self.costUSD(llmCost))",
            "LLM events: \(llmEvents)",
            "Agent disk: \(StatusFormatters.bytes(agentDisk))",
            "Agent CPU: \(Self.percent(agentCPU))",
            "Agent MEM: \(Self.percent(agentMemory))"
        ]

        if !agentNames.isEmpty {
            lines.insert("Agent names: \(agentNames.joined(separator: ", "))", at: 2)
        }

        if let topCPU = usage?.topCPUProcesses.first {
            lines.append("Top CPU: \(Self.processName(topCPU.displayName)) \(Self.percent(topCPU.cpuPercent))")
        }

        if let topMemory = usage?.topMemoryProcesses.first {
            lines.append("Top MEM: \(Self.processName(topMemory.displayName)) \(Self.percent(topMemory.memoryPercent))")
        }

        self.menuLines = lines.map(Self.compactLine)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func costUSD(_ value: Double) -> String {
        if abs(value) < 0.0001 {
            return "$0.00"
        }
        return value >= 100 ? String(format: "$%.2f", value) : String(format: "$%.4f", value)
    }

    private static func processName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Process" : trimmed
    }

    private static func compactLine(_ value: String) -> String {
        let maxLength = 30
        guard value.count > maxLength else {
            return value
        }

        return String(value.prefix(maxLength - 3)) + "..."
    }
}
