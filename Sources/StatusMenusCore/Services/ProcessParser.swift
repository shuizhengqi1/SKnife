import Foundation

public struct ProcessSample: Identifiable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let elapsed: String
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let displayName: String
    public let commandLine: String

    public init(
        pid: Int32,
        elapsed: String,
        cpuPercent: Double,
        memoryPercent: Double,
        displayName: String,
        commandLine: String
    ) {
        self.pid = pid
        self.elapsed = elapsed
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.displayName = displayName
        self.commandLine = commandLine
    }
}

public enum ProcessParser {
    public static let redactedCommand = "<command redacted>"

    public static func parsePSOutput(
        _ output: String,
        matching keywords: [String] = [],
        redactCommand: Bool = false
    ) -> [ProcessSample] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0), matching: keywords, redactCommand: redactCommand) }
    }

    private static func parseLine(
        _ line: String,
        matching keywords: [String],
        redactCommand: Bool
    ) -> ProcessSample? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("PID ") else {
            return nil
        }

        let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count == 5,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[2]),
              let memory = Double(parts[3])
        else {
            return nil
        }

        let command = String(parts[4])
        if !keywords.isEmpty {
            let lowercasedCommand = command.lowercased()
            let matched = keywords.contains { lowercasedCommand.contains($0.lowercased()) }
            guard matched else {
                return nil
            }
        }

        let displayName = command
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { URL(fileURLWithPath: String($0)).lastPathComponent }
            ?? "Process"

        return ProcessSample(
            pid: pid,
            elapsed: String(parts[1]),
            cpuPercent: cpu,
            memoryPercent: memory,
            displayName: displayName,
            commandLine: redactCommand ? redactedCommand : command
        )
    }
}
