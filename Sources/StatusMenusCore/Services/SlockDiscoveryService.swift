import Foundation

public struct SlockAgentWorkspace: Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let byteCount: Int64
    public let modifiedAt: Date?
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
        let agents = discoverAgents(rootURL: rootURL)
        let machines = discoverMachines(rootURL: rootURL)
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
            rootURL: rootURL,
            agents: agents,
            machines: machines,
            processes: processes,
            status: status
        )
    }

    private func discoverAgents(rootURL: URL) -> [SlockAgentWorkspace] {
        directoryChildren(rootURL.appendingPathComponent("agents")).map { url in
            SlockAgentWorkspace(
                id: url.lastPathComponent,
                url: url,
                byteCount: directorySize(url),
                modifiedAt: modificationDate(url)
            )
        }
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
