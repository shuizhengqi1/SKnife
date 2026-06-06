import Foundation

public struct SlockAgentWorkspace: Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let byteCount: Int64
    public let modifiedAt: Date?
    public let displayName: String
    public let description: String?
    public let avatarURL: URL?
    public let memorySections: [SlockAgentMemorySection]
}

public struct SlockAgentMemorySection: Identifiable, Equatable {
    public var id: String { title }
    public let title: String
    public let body: String
}

public struct SlockMachine: Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let hasLockOwner: Bool
    public let traceCount: Int
    public let latestTraceModifiedAt: Date?
}

public struct SlockSnapshot: Equatable {
    public let rootURL: URL
    public let agents: [SlockAgentWorkspace]
    public let machines: [SlockMachine]
    public let processes: [ProcessSample]
    public let status: ModuleStatus
}

public struct SlockDiscoveryService {
    private let fileManager: FileManager
    private let shell: Shell

    public init(fileManager: FileManager = .default, shell: Shell = .live) {
        self.fileManager = fileManager
        self.shell = shell
    }

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".slock")
    }

    public func liveSnapshot(rootURL: URL = Self.defaultRootURL) throws -> SlockSnapshot {
        let processOutput = (try? shell.run(["/bin/ps", "-axo", "pid,etime,pcpu,pmem,command"])) ?? ""
        return try snapshot(rootURL: rootURL, processOutput: processOutput)
    }

    public func snapshot(rootURL: URL, processOutput: String) throws -> SlockSnapshot {
        let resolvedRootURL = resolveRootURL(from: rootURL)
        let agents = discoverAgents(rootURL: resolvedRootURL)
        let machines = discoverMachines(rootURL: resolvedRootURL)
        let processes = ProcessParser.parsePSOutput(
            processOutput,
            matching: ["slock", "@slock-ai/daemon"],
            redactCommand: true
        )
        let hasState = !agents.isEmpty || !machines.isEmpty
        let hasProcess = !processes.isEmpty
        let hasLockOwner = machines.contains { $0.hasLockOwner }

        let status: ModuleStatus
        if hasProcess && hasLockOwner {
            status = .healthy
        } else if hasState && !hasProcess {
            status = .warning
        } else if hasProcess {
            status = .warning
        } else {
            status = .inactive
        }

        return SlockSnapshot(
            rootURL: resolvedRootURL,
            agents: agents,
            machines: machines,
            processes: processes,
            status: status
        )
    }

    private func resolveRootURL(from preferredRootURL: URL) -> URL {
        let candidates = candidateRootURLs(from: preferredRootURL)
        return candidates.first(where: hasSlockState) ?? candidates.first ?? preferredRootURL
    }

    private func candidateRootURLs(from preferredRootURL: URL) -> [URL] {
        let preferred = normalizedURL(preferredRootURL)
        var candidates: [URL] = []
        appendUnique(preferred, to: &candidates)

        let components = preferred.pathComponents
        if let agentsIndex = components.lastIndex(of: "agents"), agentsIndex > 0 {
            appendUnique(URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(upTo: agentsIndex)))), to: &candidates)
        }

        if let slockIndex = components.lastIndex(of: ".slock") {
            appendUnique(URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(through: slockIndex)))), to: &candidates)
        }

        let defaultRoot = normalizedURL(Self.defaultRootURL)
        if preferred.path == defaultRoot.path || !fileManager.fileExists(atPath: preferred.path) {
            appendUnique(defaultRoot, to: &candidates)
        }
        return candidates
    }

    private func appendUnique(_ url: URL, to candidates: inout [URL]) {
        let normalized = normalizedURL(url)
        guard !candidates.contains(where: { $0.path == normalized.path }) else {
            return
        }
        candidates.append(normalized)
    }

    private func normalizedURL(_ url: URL) -> URL {
        URL(fileURLWithPath: NSString(string: url.path).expandingTildeInPath).standardizedFileURL
    }

    private func hasSlockState(rootURL: URL) -> Bool {
        !directoryChildren(rootURL.appendingPathComponent("agents")).isEmpty
            || !directoryChildren(rootURL.appendingPathComponent("machines")).isEmpty
    }

    private func discoverAgents(rootURL: URL) -> [SlockAgentWorkspace] {
        directoryChildren(rootURL.appendingPathComponent("agents")).map { url in
            let memoryProfile = readMemoryProfile(agentURL: url)
            let metadata = readAgentMetadata(agentURL: url)
            let id = url.lastPathComponent

            return SlockAgentWorkspace(
                id: id,
                url: url,
                byteCount: directorySize(url),
                modifiedAt: modificationDate(url),
                displayName: metadata.displayName ?? memoryProfile.displayName ?? id,
                description: metadata.description ?? memoryProfile.description,
                avatarURL: metadata.avatarURL,
                memorySections: memoryProfile.memorySections
            )
        }
    }

    private func readMemoryProfile(agentURL: URL) -> AgentMemoryProfile {
        let memoryURL = agentURL.appendingPathComponent("MEMORY.md")
        guard let text = try? String(contentsOf: memoryURL, encoding: .utf8) else {
            return AgentMemoryProfile()
        }

        var displayName: String?
        var sections: [(title: String, lines: [String])] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flushSection() {
            guard let currentTitle else {
                currentLines.removeAll()
                return
            }
            sections.append((currentTitle, currentLines))
            currentLines.removeAll()
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# "), displayName == nil {
                displayName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if trimmed.hasPrefix("## ") {
                flushSection()
                currentTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if currentTitle != nil {
                currentLines.append(line)
            }
        }
        flushSection()

        let description = sections
            .first { $0.title.caseInsensitiveCompare("Role") == .orderedSame }
            .map { compactMarkdownBody($0.lines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let memorySections = sections
            .filter { $0.title.caseInsensitiveCompare("Role") != .orderedSame }
            .compactMap { section -> SlockAgentMemorySection? in
                let body = compactMarkdownBody(section.lines)
                guard !section.title.isEmpty, !body.isEmpty else {
                    return nil
                }
                return SlockAgentMemorySection(title: section.title, body: body)
            }

        return AgentMemoryProfile(
            displayName: displayName?.isEmpty == false ? displayName : nil,
            description: description,
            memorySections: memorySections
        )
    }

    private func compactMarkdownBody(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .drop(while: { $0.isEmpty })
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .joined(separator: "\n")
    }

    private func readAgentMetadata(agentURL: URL) -> AgentMetadata {
        let candidateURLs = [
            agentURL.appendingPathComponent("agent.json"),
            agentURL.appendingPathComponent("profile.json"),
            agentURL.appendingPathComponent("metadata.json"),
            agentURL.appendingPathComponent("config.json"),
            agentURL.appendingPathComponent(".slock/agent.json"),
            agentURL.appendingPathComponent(".slock/profile.json"),
            agentURL.appendingPathComponent(".slock/metadata.json"),
            agentURL.appendingPathComponent(".slock/config.json")
        ]

        var merged = AgentMetadata()
        for url in candidateURLs {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if merged.displayName == nil {
                merged.displayName = stringValue(in: object, keys: ["displayName", "display_name", "name", "agentName", "agent_name"])
            }
            if merged.description == nil {
                merged.description = stringValue(in: object, keys: ["description", "role", "summary"])
            }
            if merged.avatarURL == nil,
               let rawAvatar = stringValue(in: object, keys: ["avatarURL", "avatarUrl", "avatar_url", "avatar"])
            {
                merged.avatarURL = URL(string: rawAvatar)
            }
        }

        return merged
    }

    private func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func discoverMachines(rootURL: URL) -> [SlockMachine] {
        directoryChildren(rootURL.appendingPathComponent("machines")).map { url in
            let tracesURL = url.appendingPathComponent("traces")
            let traceURLs = fileURLs(in: tracesURL).filter { $0.pathExtension == "jsonl" }
            let latestTraceDate = traceURLs
                .compactMap(modificationDate)
                .max()
            let lockOwner = url
                .appendingPathComponent("daemon.lock")
                .appendingPathComponent("owner.json")

            return SlockMachine(
                id: url.lastPathComponent,
                url: url,
                hasLockOwner: fileManager.fileExists(atPath: lockOwner.path),
                traceCount: traceURLs.count,
                latestTraceModifiedAt: latestTraceDate
            )
        }
    }

    private func directoryChildren(_ url: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { child in
                (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func fileURLs(in url: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

private struct AgentMemoryProfile {
    var displayName: String?
    var description: String?
    var memorySections: [SlockAgentMemorySection] = []
}

private struct AgentMetadata {
    var displayName: String?
    var description: String?
    var avatarURL: URL?
}
