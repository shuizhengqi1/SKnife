import Foundation

public struct SlockAgentCostSummary: Identifiable, Equatable {
    public var id: String { agentID }

    public let agentID: String
    public let totalCostUSD: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let cacheCreationInputTokens: Int
    public let totalTokens: Int
    public let modelNames: [String]
    public let eventCount: Int
    public let lastUsageAt: Date?
}

public struct SlockCostService {
    public static let unknownAgentID = "unknown"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func summaries(rootURL: URL = SlockDiscoveryService.defaultRootURL) -> [SlockAgentCostSummary] {
        var builders: [String: SlockAgentCostSummaryBuilder] = [:]

        for traceURL in traceFileURLs(rootURL: rootURL) {
            guard let lines = try? String(contentsOf: traceURL, encoding: .utf8).components(separatedBy: .newlines) else {
                continue
            }

            for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let event = usageEvent(from: line) else {
                    continue
                }
                builders[event.agentID, default: SlockAgentCostSummaryBuilder(agentID: event.agentID)].add(event)
            }
        }

        return builders.values
            .map(\.summary)
            .sorted {
                if $0.totalCostUSD == $1.totalCostUSD {
                    return $0.agentID.localizedStandardCompare($1.agentID) == .orderedAscending
                }
                return $0.totalCostUSD > $1.totalCostUSD
            }
    }

    private func traceFileURLs(rootURL: URL) -> [URL] {
        let machinesURL = normalizedURL(rootURL).appendingPathComponent("machines")
        guard let machineURLs = try? fileManager.contentsOfDirectory(
            at: machinesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return machineURLs.flatMap { machineURL in
            let tracesURL = machineURL.appendingPathComponent("traces")
            guard let traceURLs = try? fileManager.contentsOfDirectory(
                at: tracesURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [URL]()
            }

            return traceURLs
                .filter { $0.pathExtension == "jsonl" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
    }

    private func usageEvent(from line: String) -> SlockUsageEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let eventName = object["name"] as? String ?? ""
        guard eventName == "daemon.runtime.telemetry.token_usage" || eventName == "token_usage" || eventName.hasSuffix(".token_usage") else {
            return nil
        }

        guard let attrs = object["attrs"] as? [String: Any] else {
            return nil
        }

        let agentID = stringValue(attrs["agentId"])
            ?? stringValue(object["agentId"])
            ?? Self.unknownAgentID
        let models = modelNames(from: attrs)
        let inputTokens = intValue(attrs["inputTokens"]) ?? intValue(attrs["modelUsageInputTokens"]) ?? 0
        let outputTokens = intValue(attrs["outputTokens"]) ?? intValue(attrs["modelUsageOutputTokens"]) ?? 0
        let cachedInputTokens = intValue(attrs["cachedInputTokens"]) ?? intValue(attrs["modelUsageCachedInputTokens"]) ?? 0
        let cacheCreationInputTokens = intValue(attrs["cacheCreationInputTokens"]) ?? intValue(attrs["modelUsageCacheCreationInputTokens"]) ?? 0
        let totalTokens = intValue(attrs["totalTokens"])
            ?? inputTokens + outputTokens + cachedInputTokens + cacheCreationInputTokens

        return SlockUsageEvent(
            agentID: agentID,
            costUSD: doubleValue(attrs["totalCostUsd"])
                ?? doubleValue(attrs["modelUsageCostUsd"])
                ?? doubleValue(attrs["costUSD"])
                ?? 0,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            totalTokens: totalTokens,
            modelNames: models,
            usageAt: dateValue(object["start_time"]) ?? dateValue(object["end_time"])
        )
    }

    private func modelNames(from attrs: [String: Any]) -> [String] {
        var names: Set<String> = []
        if let model = stringValue(attrs["model"]) {
            names.insert(model)
        }
        if let rawModels = stringValue(attrs["modelUsageModels"]) {
            for value in rawModels.split(separator: ",") {
                let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !model.isEmpty {
                    names.insert(model)
                }
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Double, value.isFinite {
            return Int(value)
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? String, let number = Double(value), number.isFinite {
            return number
        }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        guard let string = value as? String else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private func normalizedURL(_ url: URL) -> URL {
        URL(fileURLWithPath: NSString(string: url.path).expandingTildeInPath).standardizedFileURL
    }
}

private struct SlockUsageEvent {
    let agentID: String
    let costUSD: Double
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let cacheCreationInputTokens: Int
    let totalTokens: Int
    let modelNames: [String]
    let usageAt: Date?
}

private struct SlockAgentCostSummaryBuilder {
    let agentID: String
    var totalCostUSD: Double = 0
    var inputTokens = 0
    var outputTokens = 0
    var cachedInputTokens = 0
    var cacheCreationInputTokens = 0
    var totalTokens = 0
    var modelNames: Set<String> = []
    var eventCount = 0
    var lastUsageAt: Date?

    mutating func add(_ event: SlockUsageEvent) {
        totalCostUSD += event.costUSD
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cachedInputTokens += event.cachedInputTokens
        cacheCreationInputTokens += event.cacheCreationInputTokens
        totalTokens += event.totalTokens
        modelNames.formUnion(event.modelNames)
        eventCount += 1
        if let usageAt = event.usageAt, lastUsageAt == nil || usageAt > (lastUsageAt ?? usageAt) {
            lastUsageAt = usageAt
        }
    }

    var summary: SlockAgentCostSummary {
        SlockAgentCostSummary(
            agentID: agentID,
            totalCostUSD: totalCostUSD,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            totalTokens: totalTokens,
            modelNames: modelNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            eventCount: eventCount,
            lastUsageAt: lastUsageAt
        )
    }
}
