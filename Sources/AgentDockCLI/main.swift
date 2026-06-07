import Darwin
import Foundation
import StatusMenusCore

@main
enum AgentDockCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("agentdock: \(error)\n", stderr)
            fputs(Self.usage, stderr)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            print(usage)
            return
        }

        let rest = Array(arguments.dropFirst())
        switch command {
        case "status":
            try printStatus(rest)
        case "storage":
            try printStorage(rest)
        case "slock":
            try printSlock(rest)
        case "modules":
            try await printModules(rest)
        case "app":
            try openApp(rest)
        case "help", "--help", "-h":
            print(usage)
        default:
            throw CLIError.message("unknown command \(command)")
        }
    }

    private static func printStatus(_ arguments: [String]) throws {
        let root = slockRoot(from: arguments)
        let processOutput = (try? Shell.live.run(["/bin/ps", "-axo", "pid,etime,pcpu,pmem,command"])) ?? ""
        let slock = try? SlockDiscoveryService().snapshot(rootURL: root, processOutput: processOutput)
        let slockCosts = slock.map { SlockCostService().summaries(rootURL: $0.rootURL) } ?? []
        let usage = UsageService().snapshot(processOutput: processOutput)
        let storage = StorageService().snapshot(includeFolderSizes: false, includeDiskCapacity: true)
        let summary = MenuBarStatusSummary(slock: slock, usage: usage, slockCosts: slockCosts)

        if arguments.contains("--json") {
            let storagePayload: [String: Any] = [
                "usedBytes": storage.disk.used,
                "availableBytes": storage.disk.available,
                "capacityBytes": storage.disk.capacity
            ]
            let slockPayload: [String: Any] = [
                "status": slock?.status.label ?? "Unavailable",
                "agentCount": slock?.agents.count ?? 0,
                "processCount": slock?.processes.count ?? 0,
                "llmCostUSD": slockCosts.reduce(0) { $0 + $1.totalCostUSD },
                "llmUsageEvents": slockCosts.reduce(0) { $0 + $1.eventCount },
                "llmTotalTokens": slockCosts.reduce(0) { $0 + $1.totalTokens },
                "llmCosts": slockCosts.map(costDictionary)
            ]
            let usagePayload: [String: Any] = [
                "topCPU": usage.topCPUProcesses.first.map(processDictionary) ?? NSNull(),
                "topMemory": usage.topMemoryProcesses.first.map(processDictionary) ?? NSNull()
            ]
            let payload: [String: Any] = [
                "app": "AgentDock",
                "buttonTitle": summary.buttonTitle,
                "storage": storagePayload,
                "slock": slockPayload,
                "usage": usagePayload
            ]
            try printJSON(payload)
            return
        }

        print("AgentDock")
        print("Storage: \(StatusFormatters.bytes(storage.disk.used)) used, \(StatusFormatters.bytes(storage.disk.available)) available")
        if let slock {
            print("Slock: \(slock.status.label), agents \(slock.agents.count), processes \(slock.processes.count)")
        } else {
            print("Slock: unavailable")
        }
        for line in summary.menuLines {
            print(line)
        }
    }

    private static func printStorage(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.message("missing storage subcommand")
        }
        let rest = Array(arguments.dropFirst())
        let root = pathValue(from: rest) ?? FileManager.default.homeDirectoryForCurrentUser
        let depth = intValue(after: "--depth", in: rest) ?? 3
        let service = StorageService()

        switch subcommand {
        case "scan":
            let analysis = service.analysis(rootURL: root, maxDepth: depth, includeHidden: rest.contains("--hidden"))
            let indexResult = saveStorageIndexIfNeeded(analysis, arguments: rest)
            if rest.contains("--json") {
                var payload = analysisDictionary(analysis)
                payload["localIndex"] = indexResultDictionary(indexResult)
                try printJSON(payload)
            } else {
                print("Scanned \(analysis.root.url.path)")
                print("Indexed files: \(analysis.indexedFileCount)")
                print("Used in tree: \(StatusFormatters.bytes(analysis.root.byteCount))")
                print("Cleanup candidates: \(analysis.cleanupCandidates.count)")
                print("Scan time: \(StatusFormatters.duration(analysis.scanDuration))")
                switch indexResult {
                case .saved(let databaseURL):
                    print("Local index: saved to \(databaseURL.path)")
                case .skipped:
                    print("Local index: skipped")
                case .failed(let message):
                    print("Local index: failed - \(message)")
                }
            }
        case "index":
            let databasePath = StorageIndexStore.defaultDatabaseURL.path
            let analysis = try StorageIndexStore().latestAnalysis()
            guard let analysis else {
                if rest.contains("--json") {
                    try printJSON([
                        "available": false,
                        "databasePath": databasePath
                    ])
                } else {
                    print("No local storage index found at \(databasePath)")
                }
                return
            }
            if rest.contains("--json") {
                var payload = analysisDictionary(analysis)
                payload["available"] = true
                payload["databasePath"] = databasePath
                try printJSON(payload)
            } else {
                print("Local index: \(databasePath)")
                print("Root: \(analysis.root.url.path)")
                print("Last scan: \(StatusFormatters.shortDateTime(analysis.scanFinishedAt))")
                print("Scan time: \(StatusFormatters.duration(analysis.scanDuration))")
                print("Indexed files: \(analysis.indexedFileCount)")
                print("Used in tree: \(StatusFormatters.bytes(analysis.root.byteCount))")
                print("Cleanup candidates: \(analysis.cleanupCandidates.count)")
            }
        case "top":
            let limit = intValue(after: "--limit", in: rest) ?? 20
            let analysis = service.analysis(rootURL: root, maxDepth: depth, includeHidden: rest.contains("--hidden"))
            let nodes = Array(analysis.rankedNodes.prefix(max(1, limit)))
            if rest.contains("--json") {
                try printJSON(nodes.map(nodeDictionary))
            } else {
                for node in nodes {
                    print("\(StatusFormatters.bytes(node.byteCount))\t\(node.url.path)")
                }
            }
        case "clean-plan":
            let analysis = service.analysis(rootURL: root, maxDepth: depth, includeHidden: rest.contains("--hidden"))
            let candidates = rest.contains("--safe-only")
                ? analysis.cleanupCandidates.filter { $0.risk == .safe }
                : analysis.cleanupCandidates
            if rest.contains("--json") {
                try printJSON(candidates.map(candidateDictionary))
            } else {
                for candidate in candidates {
                    print("\(candidate.risk.rawValue)\t\(StatusFormatters.bytes(candidate.byteCount))\t\(candidate.url.path)\t\(candidate.reason)")
                }
            }
        case "trash":
            guard let target = positionalValue(in: rest) ?? stringValue(after: "--path", in: rest) else {
                throw CLIError.message("storage trash requires a path")
            }
            let results = service.moveURLsToTrash([expandPath(target)])
            if rest.contains("--json") {
                try printJSON(results.map(cleanupResultDictionary))
            } else {
                for result in results {
                    print("\(result.succeeded ? "ok" : "failed")\t\(result.url.path)\t\(result.message)")
                }
            }
        default:
            throw CLIError.message("unknown storage subcommand \(subcommand)")
        }
    }

    private static func saveStorageIndexIfNeeded(_ analysis: StorageAnalysis, arguments: [String]) -> StorageIndexResult {
        if arguments.contains("--no-index") {
            return .skipped
        }

        do {
            let store = try StorageIndexStore()
            try store.save(analysis)
            return .saved(store.databaseURL)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func printSlock(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.message("missing slock subcommand")
        }
        let rest = Array(arguments.dropFirst())
        let root = slockRoot(from: rest)
        let snapshot = try SlockDiscoveryService().liveSnapshot(rootURL: root)

        switch subcommand {
        case "list":
            if rest.contains("--json") {
                try printJSON(snapshot.agents.map(agentDictionary))
            } else {
                for agent in snapshot.agents {
                    print("\(agent.id)\t\(agent.displayName)\t\(agent.url.path)")
                }
            }
        case "show":
            guard let id = positionalValue(in: rest),
                  let agent = snapshot.agents.first(where: { $0.id == id || $0.displayName == id })
            else {
                throw CLIError.message("agent not found")
            }
            if rest.contains("--json") {
                try printJSON(agentDictionary(agent))
            } else {
                print("ID: \(agent.id)")
                print("Name: \(agent.displayName)")
                print("Path: \(agent.url.path)")
                print("Description: \(agent.description ?? "")")
                for section in agent.memorySections {
                    print("\n## \(section.title)\n\(section.body)")
                }
            }
        case "set-description":
            let values = positionalValues(in: rest)
            guard let id = values.first,
                  let agent = snapshot.agents.first(where: { $0.id == id || $0.displayName == id })
            else {
                throw CLIError.message("agent not found")
            }
            let description = values.dropFirst().joined(separator: " ")
            guard !description.isEmpty else {
                throw CLIError.message("set-description requires text")
            }
            try SlockDiscoveryService().saveMemoryDraft(
                agentURL: agent.url,
                draft: SlockAgentMemoryDraft(
                    displayName: agent.displayName,
                    description: description,
                    memorySections: agent.memorySections
                )
            )
            print("Updated description for \(agent.id)")
        case "costs":
            let costs = SlockCostService().summaries(rootURL: snapshot.rootURL)
            if rest.contains("--json") {
                try printJSON(costs.map(costDictionary))
            } else if costs.isEmpty {
                print("No local LLM cost telemetry found")
            } else {
                for summary in costs {
                    print("\(summary.agentID)\t\(costUSD(summary.totalCostUSD))\t\(summary.eventCount) events\t\(tokenCount(summary.totalTokens)) tokens")
                }
            }
        default:
            throw CLIError.message("unknown slock subcommand \(subcommand)")
        }
    }

    @MainActor
    private static func printModules(_ arguments: [String]) throws {
        guard arguments.first == "list" || arguments.isEmpty else {
            throw CLIError.message("unknown modules subcommand \(arguments[0])")
        }
        let store = ModuleStore()
        let rows = ModuleRegistry.builtIns.map { descriptor in
            [
                "id": descriptor.id.rawValue,
                "title": descriptor.title,
                "enabled": store.isEnabled(descriptor.id),
                "subtitle": descriptor.subtitle
            ] as [String: Any]
        }
        if arguments.contains("--json") {
            try printJSON(rows)
        } else {
            for row in rows {
                print("\(row["id"] ?? "")\t\(row["enabled"] ?? false)\t\(row["title"] ?? "")")
            }
        }
    }

    private static func openApp(_ arguments: [String]) throws {
        guard arguments.first == "open" || arguments.isEmpty else {
            throw CLIError.message("unknown app subcommand \(arguments[0])")
        }
        if let status = try? Shell.live.run(["/usr/bin/open", "-a", "AgentDock"]) {
            if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print(status)
            }
            return
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let stagedAppURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AgentDock.app")
        guard FileManager.default.fileExists(atPath: stagedAppURL.path) else {
            throw CLIError.message("AgentDock.app is not installed or staged next to this CLI")
        }
        _ = try Shell.live.run(["/usr/bin/open", stagedAppURL.path])
        print("Opened \(stagedAppURL.path)")
    }

    private static func slockRoot(from arguments: [String]) -> URL {
        stringValue(after: "--root", in: arguments).map(expandPath) ?? SlockDiscoveryService.defaultRootURL
    }

    private static func pathValue(from arguments: [String]) -> URL? {
        stringValue(after: "--path", in: arguments).map(expandPath)
    }

    private static func stringValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(arguments.index(after: index))
        else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    private static func intValue(after flag: String, in arguments: [String]) -> Int? {
        stringValue(after: flag, in: arguments).flatMap(Int.init)
    }

    private static func positionalValue(in arguments: [String]) -> String? {
        positionalValues(in: arguments).first
    }

    private static func positionalValues(in arguments: [String]) -> [String] {
        let flagsWithValues: Set<String> = ["--root", "--path", "--depth", "--limit"]
        var values: [String] = []
        var shouldSkipNext = false
        for argument in arguments {
            if shouldSkipNext {
                shouldSkipNext = false
                continue
            }
            if flagsWithValues.contains(argument) {
                shouldSkipNext = true
                continue
            }
            if argument.hasPrefix("-") {
                continue
            }
            values.append(argument)
        }
        return values
    }

    private static func expandPath(_ value: String) -> URL {
        URL(fileURLWithPath: NSString(string: value).expandingTildeInPath).standardizedFileURL
    }

    private static func printJSON(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        print("")
    }

    private static func analysisDictionary(_ analysis: StorageAnalysis) -> [String: Any] {
        [
            "root": nodeDictionary(analysis.root),
            "disk": [
                "usedBytes": analysis.disk.used,
                "availableBytes": analysis.disk.available,
                "capacityBytes": analysis.disk.capacity
            ],
            "indexedFileCount": analysis.indexedFileCount,
            "scanStartedAt": dateDictionaryValue(analysis.scanStartedAt),
            "scanFinishedAt": dateDictionaryValue(analysis.scanFinishedAt),
            "scanDurationSeconds": analysis.scanDuration,
            "rankedNodes": analysis.rankedNodes.map(nodeDictionary),
            "cleanupCandidates": analysis.cleanupCandidates.map(candidateDictionary),
            "scanLog": analysis.scanLog
        ]
    }

    private static func indexResultDictionary(_ result: StorageIndexResult) -> [String: Any] {
        switch result {
        case .saved(let databaseURL):
            return [
                "saved": true,
                "databasePath": databaseURL.path
            ]
        case .skipped:
            return [
                "saved": false,
                "skipped": true
            ]
        case .failed(let message):
            return [
                "saved": false,
                "error": message
            ]
        }
    }

    private static func dateDictionaryValue(_ date: Date?) -> Any {
        date?.timeIntervalSince1970 ?? NSNull()
    }

    private static func nodeDictionary(_ node: StorageNode) -> [String: Any] {
        [
            "title": node.title,
            "path": node.url.path,
            "byteCount": node.byteCount,
            "isDirectory": node.isDirectory,
            "risk": node.risk.rawValue,
            "children": node.children.map(nodeDictionary)
        ]
    }

    private static func candidateDictionary(_ candidate: StorageCleanupCandidate) -> [String: Any] {
        [
            "title": candidate.title,
            "path": candidate.url.path,
            "byteCount": candidate.byteCount,
            "risk": candidate.risk.rawValue,
            "reason": candidate.reason
        ]
    }

    private static func cleanupResultDictionary(_ result: StorageCleanupResult) -> [String: Any] {
        [
            "path": result.url.path,
            "trashedPath": result.trashedURL?.path ?? NSNull(),
            "succeeded": result.succeeded,
            "message": result.message
        ]
    }

    private static func agentDictionary(_ agent: SlockAgentWorkspace) -> [String: Any] {
        [
            "id": agent.id,
            "name": agent.displayName,
            "path": agent.url.path,
            "byteCount": agent.byteCount,
            "description": agent.description ?? NSNull(),
            "avatarURL": agent.avatarURL?.absoluteString ?? NSNull(),
            "memorySections": agent.memorySections.map {
                [
                    "title": $0.title,
                    "body": $0.body
                ]
            }
        ]
    }

    private static func costDictionary(_ summary: SlockAgentCostSummary) -> [String: Any] {
        [
            "agentID": summary.agentID,
            "totalCostUSD": summary.totalCostUSD,
            "inputTokens": summary.inputTokens,
            "outputTokens": summary.outputTokens,
            "cachedInputTokens": summary.cachedInputTokens,
            "cacheCreationInputTokens": summary.cacheCreationInputTokens,
            "totalTokens": summary.totalTokens,
            "models": summary.modelNames,
            "eventCount": summary.eventCount,
            "lastUsageAt": dateDictionaryValue(summary.lastUsageAt)
        ]
    }

    private static func processDictionary(_ process: ProcessSample) -> [String: Any] {
        [
            "pid": process.pid,
            "displayName": process.displayName,
            "cpuPercent": process.cpuPercent,
            "memoryPercent": process.memoryPercent,
            "elapsed": process.elapsed
        ]
    }

    private static func costUSD(_ value: Double) -> String {
        if abs(value) < 0.0001 {
            return "$0.00"
        }
        return value >= 100 ? String(format: "$%.2f", value) : String(format: "$%.4f", value)
    }

    private static func tokenCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private static let usage = """

    Usage:
      agentdock status [--json] [--root ~/.slock]
      agentdock storage scan [--path ~] [--depth 3] [--hidden] [--no-index] [--json]
      agentdock storage index [--json]
      agentdock storage top [--path ~] [--depth 3] [--limit 20] [--json]
      agentdock storage clean-plan [--path ~] [--depth 3] [--safe-only] [--json]
      agentdock storage trash <path> [--json]
      agentdock slock list [--root ~/.slock] [--json]
      agentdock slock show <agent-id> [--root ~/.slock] [--json]
      agentdock slock set-description <agent-id> <text> [--root ~/.slock]
      agentdock slock costs [--root ~/.slock] [--json]
      agentdock modules list [--json]
      agentdock app open

    """
}

private enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private enum StorageIndexResult {
    case saved(URL)
    case skipped
    case failed(String)
}
