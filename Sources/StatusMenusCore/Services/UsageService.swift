import Foundation

public struct UsageSnapshot: Equatable {
    public let capturedAt: Date
    public let memoryTotalBytes: UInt64
    public let topCPUProcesses: [ProcessSample]
    public let topMemoryProcesses: [ProcessSample]
}

public struct UsageService {
    private let shell: Shell

    public init(shell: Shell = .live) {
        self.shell = shell
    }

    public func snapshot() -> UsageSnapshot {
        let output = (try? shell.run(["/bin/ps", "-axo", "pid,etime,pcpu,pmem,command"])) ?? ""
        return snapshot(processOutput: output)
    }

    public func snapshot(processOutput: String) -> UsageSnapshot {
        let processes = ProcessParser.parsePSOutput(processOutput, redactCommand: false)

        return UsageSnapshot(
            capturedAt: Date(),
            memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
            topCPUProcesses: Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(8)),
            topMemoryProcesses: Array(processes.sorted { $0.memoryPercent > $1.memoryPercent }.prefix(8))
        )
    }
}
