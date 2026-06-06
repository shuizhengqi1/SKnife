import Foundation
import StatusMenusCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
enum StatusMenusCoreChecks {
    static func main() async throws {
        try run("registry contains required built-ins", registryContainsRequiredBuiltInsInStableOrder)
        try await run("module store persists disabled modules", moduleStorePersistsDisabledModulesAndKeepsManagerEnabled)
        try await run("module store defaults refresh interval", moduleStoreDefaultsRefreshInterval)
        try run("Slock discovery scans all directories", discoveryScansAllAgentAndMachineDirectoriesWithoutFixedIDs)
        try run("Slock discovery reads agent profile metadata", discoveryReadsAgentProfileMetadata)
        try run("Slock discovery writes agent memory draft", discoveryWritesAgentMemoryDraft)
        try run("Slock discovery resolves nested paths", discoveryResolvesNestedSlockPaths)
        try run("Slock discovery reports inactive", discoveryReportsInactiveWhenNoSlockStateExists)
        try run("Slock discovery detects current home when present", discoveryDetectsCurrentHomeWhenPresent)
        try run("menu bar summary includes Slock and usage details", menuBarSummaryIncludesSlockAndUsageDetails)
        try run("shell captures large output", shellCapturesLargeOutputWithoutDeadlock)
        try run("process parser redacts command", parsePSOutputFiltersKeywordsAndRedactsCommand)
        try run("process parser keeps display name", parsePSOutputKeepsDisplayNameWhenCommandIsRedacted)
        try run("byte formatting uses file units", byteFormattingUsesFileStyleUnits)
        try run("percent formatting handles zero total", percentFormattingHandlesZeroTotal)
        try run("storage summary skips recursive folder sizes", storageSummarySnapshotSkipsRecursiveFolderSizes)
        try run("storage scan modes hide raw depth behind presets", storageScanModesHideRawDepthBehindPresets)
        try run("storage analysis builds ranked tree and cleanup candidates", storageAnalysisBuildsRankedTreeAndCleanupCandidates)
        try run("Slock metric sample summarizes snapshot and caps history", slockMetricSampleSummarizesSnapshotAndCapsHistory)
        try run("storage placeholder skips disk capacity", storagePlaceholderSkipsDiskCapacity)
        try run("storage empty snapshot has no work", storageEmptySnapshotHasNoWork)
        print("StatusMenusCoreChecks passed")
    }

    private static func run(_ name: String, _ check: () throws -> Void) throws {
        do {
            try check()
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            throw error
        }
    }

    private static func run(_ name: String, _ check: () async throws -> Void) async throws {
        do {
            try await check()
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            throw error
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw CheckFailure.failed(message)
        }
    }

    private static func expectUnwrapped<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw CheckFailure.failed(message)
        }
        return value
    }

    private static func registryContainsRequiredBuiltInsInStableOrder() throws {
        let ids = ModuleRegistry.builtIns.map(\.id)

        try expect(ids == [.storage, .slock, .usage, .modules], "unexpected built-in module order: \(ids)")
    }

    @MainActor
    private static func moduleStorePersistsDisabledModulesAndKeepsManagerEnabled() async throws {
        let suiteName = "StatusMenusTests.ModuleStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ModuleStore(userDefaults: defaults)

        try expect(store.isEnabled(.storage), "storage should be enabled by default")

        store.setEnabled(false, for: .storage)
        store.setEnabled(false, for: .modules)

        try expect(!store.isEnabled(.storage), "storage should be disabled")
        try expect(store.isEnabled(.modules), "module manager must stay enabled")

        let restored = ModuleStore(userDefaults: defaults)
        try expect(!restored.isEnabled(.storage), "storage disabled state should persist")
        try expect(restored.isEnabled(.modules), "module manager should restore as enabled")
    }

    @MainActor
    private static func moduleStoreDefaultsRefreshInterval() async throws {
        let suiteName = "StatusMenusTests.ModuleStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ModuleStore(userDefaults: defaults)

        try expect(store.refreshInterval == 5, "refresh interval should default to 5 seconds")
        try expect(store.effectiveRefreshInterval == 5, "effective refresh interval should use the default")

        store.refreshInterval = 0.25
        try expect(store.effectiveRefreshInterval == 1, "effective refresh interval should clamp very small values")
    }

    private static func discoveryScansAllAgentAndMachineDirectoriesWithoutFixedIDs() throws {
        let root = try makeTemporarySlockRoot()
        let agentA = root.appendingPathComponent("agents/agent-a")
        let agentB = root.appendingPathComponent("agents/agent-b")
        let traces = root.appendingPathComponent("machines/machine-a/traces")
        let lock = root.appendingPathComponent("machines/machine-a/daemon.lock")
        try FileManager.default.createDirectory(at: agentA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: traces, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try "trace\n".write(to: traces.appendingPathComponent("daemon-trace.jsonl"), atomically: true, encoding: .utf8)
        try "{}\n".write(to: lock.appendingPathComponent("owner.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("agent-proxy-tokens/agent-a"),
            withIntermediateDirectories: true
        )
        try "secret".write(
            to: root.appendingPathComponent("agent-proxy-tokens/agent-a/pid-1.token"),
            atomically: true,
            encoding: .utf8
        )

        let processOutput = """
        PID ELAPSED %CPU %MEM COMMAND
        42 00:10 1.5 0.4 /usr/local/bin/node /tmp/@slock-ai/daemon --token secret
        """

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: processOutput)

        try expect(snapshot.agents.map(\.id).sorted() == ["agent-a", "agent-b"], "agents were not discovered dynamically")
        try expect(snapshot.machines.map(\.id) == ["machine-a"], "machine directory was not discovered")
        try expect(snapshot.machines.first?.traceCount == 1, "trace count should be 1")
        try expect(snapshot.machines.first?.hasLockOwner == true, "lock owner should be present")
        try expect(snapshot.processes.first?.commandLine == ProcessParser.redactedCommand, "Slock command should be redacted")
        try expect(snapshot.status == .healthy, "snapshot should be healthy")
    }

    private static func discoveryReadsAgentProfileMetadata() throws {
        let root = try makeTemporarySlockRoot()
        let agent = root.appendingPathComponent("agents/agent-a")
        try FileManager.default.createDirectory(at: agent.appendingPathComponent(".slock"), withIntermediateDirectories: true)
        try """
        # testAgent

        ## Role
        General Slock AI agent available for coding, research, and debugging.

        ## Key Knowledge
        - Knows the AgentDock app structure.
        - Tracks local Slock workspaces.

        ## Active Context
        - Working in the StatusMenus repo.
        """.write(to: agent.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        try """
        {
          "avatar_url": "https://cdn.example.test/testAgent.png"
        }
        """.write(to: agent.appendingPathComponent(".slock/profile.json"), atomically: true, encoding: .utf8)

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: "")
        let profile = try expectUnwrapped(snapshot.agents.first, "agent should be discovered")

        try expect(profile.displayName == "testAgent", "display name should come from MEMORY.md")
        try expect(profile.avatarURL?.absoluteString == "https://cdn.example.test/testAgent.png", "avatar URL should come from local metadata")
        try expect(profile.description == "General Slock AI agent available for coding, research, and debugging.", "description should come from Role section")
        try expect(profile.memorySections.map(\.title) == ["Key Knowledge", "Active Context"], "memory sections should be extracted")
        try expect(profile.memorySections.first?.body.contains("AgentDock app structure") == true, "memory section body should be preserved")
    }

    private static func discoveryWritesAgentMemoryDraft() throws {
        let root = try makeTemporarySlockRoot()
        let agent = root.appendingPathComponent("agents/agent-a")
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        try """
        # oldAgent

        ## Role
        Old local description.
        """.write(to: agent.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)

        let draft = SlockAgentMemoryDraft(
            displayName: "editedAgent",
            description: "Updated local description.",
            memorySections: [
                SlockAgentMemorySection(title: "Working Notes", body: "- Keep edits local.\n- Refresh after save."),
                SlockAgentMemorySection(title: "Preferences", body: "Use SwiftUI.")
            ]
        )

        try SlockDiscoveryService().saveMemoryDraft(agentURL: agent, draft: draft)

        let text = try String(contentsOf: agent.appendingPathComponent("MEMORY.md"), encoding: .utf8)
        try expect(text.contains("# editedAgent"), "saved memory should include display name")
        try expect(text.contains("## Role\nUpdated local description."), "saved memory should include description")
        try expect(text.contains("## Working Notes\n- Keep edits local."), "saved memory should include custom sections")

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: "")
        let profile = try expectUnwrapped(snapshot.agents.first, "agent should still be discovered")
        try expect(profile.displayName == "editedAgent", "edited display name should be read back")
        try expect(profile.description == "Updated local description.", "edited description should be read back")
        try expect(profile.memorySections.map(\.title) == ["Working Notes", "Preferences"], "edited memory sections should be read back")
    }

    private static func discoveryReportsInactiveWhenNoSlockStateExists() throws {
        let root = try makeTemporaryDirectory()

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: "")

        try expect(snapshot.agents.isEmpty, "agents should be empty")
        try expect(snapshot.machines.isEmpty, "machines should be empty")
        try expect(snapshot.status == .inactive, "status should be inactive")
    }

    private static func discoveryDetectsCurrentHomeWhenPresent() throws {
        let root = SlockDiscoveryService.defaultRootURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            return
        }

        let hasLocalState = !directoryChildren(root.appendingPathComponent("agents")).isEmpty
            || !directoryChildren(root.appendingPathComponent("machines")).isEmpty
        guard hasLocalState else {
            return
        }

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: "")
        try expect(!snapshot.agents.isEmpty || !snapshot.machines.isEmpty, "current home Slock state should be discovered")
    }

    private static func discoveryResolvesNestedSlockPaths() throws {
        let root = try makeTemporarySlockRoot()
        let agent = root.appendingPathComponent("agents/agent-workspace")
        try FileManager.default.createDirectory(at: agent.appendingPathComponent(".slock"), withIntermediateDirectories: true)

        let fromAgentWorkspace = try SlockDiscoveryService().snapshot(rootURL: agent, processOutput: "")
        try expect(fromAgentWorkspace.rootURL.standardizedFileURL == root.standardizedFileURL, "agent workspace path should resolve to Slock root")
        try expect(fromAgentWorkspace.agents.map(\.id) == ["agent-workspace"], "agent workspace scan should still find the agent")

        let fromAgentsDirectory = try SlockDiscoveryService().snapshot(rootURL: root.appendingPathComponent("agents"), processOutput: "")
        try expect(fromAgentsDirectory.rootURL.standardizedFileURL == root.standardizedFileURL, "agents directory path should resolve to Slock root")
        try expect(fromAgentsDirectory.agents.map(\.id) == ["agent-workspace"], "agents directory scan should still find the agent")
    }

    private static func menuBarSummaryIncludesSlockAndUsageDetails() throws {
        let root = try makeTemporarySlockRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agents/agent-a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agents/agent-b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("machines/machine-a/traces"), withIntermediateDirectories: true)
        let slockOutput = """
        PID ELAPSED %CPU %MEM COMMAND
        42 00:10 1.5 0.4 /usr/local/bin/node /tmp/@slock-ai/daemon --token secret
        """
        let slock = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: slockOutput)
        let usageOutput = """
        PID ELAPSED %CPU %MEM COMMAND
        101 00:20 9.0 2.0 /usr/local/bin/heavy
        102 00:30 1.0 5.0 /usr/local/bin/memoryhog
        """
        let usage = UsageService(shell: Shell { _ in usageOutput }).snapshot()

        let summary = MenuBarStatusSummary(slock: slock, usage: usage)

        try expect(summary.buttonTitle == "AgentDock 2A", "button title should include compact agent count")
        try expect(summary.menuLines.contains("Agents: 2"), "menu should include agent count")
        try expect(summary.menuLines.contains("Agent names: agent-a, agent-b"), "menu should include agent display names")
        try expect(summary.menuLines.contains("Agent CPU: 1.5%"), "menu should include Slock agent CPU")
        try expect(summary.menuLines.contains("Agent MEM: 0.4%"), "menu should include Slock agent memory")
        try expect(summary.menuLines.contains("Top CPU: heavy 9.0%"), "menu should include top CPU process")
        try expect(summary.menuLines.contains("Top MEM: memoryhog 5.0%"), "menu should include top memory process")
        try expect(summary.menuLines.allSatisfy { $0.count <= 30 }, "menu lines should stay compact")
    }

    private static func parsePSOutputFiltersKeywordsAndRedactsCommand() throws {
        let output = """
        PID ELAPSED %CPU %MEM COMMAND
        100 01:02 4.5 1.1 /usr/local/bin/node /tmp/@slock-ai/daemon --server-url https://api.slock.ai --token secret
        200 00:01 0.1 0.1 /bin/zsh
        """

        let rows = ProcessParser.parsePSOutput(output, matching: ["slock"], redactCommand: true)

        try expect(rows.count == 1, "expected one matching process")
        try expect(rows[0].pid == 100, "pid should parse")
        try expect(rows[0].cpuPercent == 4.5, "cpu should parse")
        try expect(rows[0].memoryPercent == 1.1, "memory should parse")
        try expect(rows[0].commandLine == ProcessParser.redactedCommand, "command should be redacted")
    }

    private static func shellCapturesLargeOutputWithoutDeadlock() throws {
        let output = try Shell.live.run(["/bin/sh", "-c", "yes slock | head -n 50000"])
        try expect(output.count > 250_000, "large shell output should be captured")
    }

    private static func parsePSOutputKeepsDisplayNameWhenCommandIsRedacted() throws {
        let output = """
        PID ELAPSED %CPU %MEM COMMAND
        321 00:05 0.3 0.2 /opt/homebrew/bin/node /tmp/@slock-ai/daemon
        """

        let rows = ProcessParser.parsePSOutput(output, matching: ["slock"], redactCommand: true)

        try expect(rows.first?.displayName == "node", "display name should survive redaction")
    }

    private static func byteFormattingUsesFileStyleUnits() throws {
        try expect(StatusFormatters.bytes(1_024) == "1 KB", "1024 should format as 1 KB")
        try expect(StatusFormatters.bytes(1_048_576) == "1 MB", "1048576 should format as 1 MB")
    }

    private static func percentFormattingHandlesZeroTotal() throws {
        try expect(StatusFormatters.percent(used: 50, total: 200) == "25%", "50/200 should format as 25%")
        try expect(StatusFormatters.percent(used: 50, total: 0) == "0%", "zero total should format as 0%")
    }

    private static func storageSummarySnapshotSkipsRecursiveFolderSizes() throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Downloads"),
            withIntermediateDirectories: true
        )
        try "demo".write(
            to: root.appendingPathComponent("Downloads/file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = StorageService().snapshot(homeURL: root, includeFolderSizes: false)

        try expect(!snapshot.folders.isEmpty, "summary should still list folders")
        try expect(snapshot.folders.allSatisfy { $0.byteCount == nil }, "summary mode must not calculate folder sizes")
    }

    private static func storageScanModesHideRawDepthBehindPresets() throws {
        try expect(StorageScanMode.fast.maxDepth < StorageScanMode.balanced.maxDepth, "fast should scan less deeply than balanced")
        try expect(StorageScanMode.balanced.maxDepth < StorageScanMode.deep.maxDepth, "balanced should scan less deeply than deep")
        try expect(StorageScanMode.balanced.label == "Balanced", "balanced should be the user-facing default")
        try expect(!StorageScanMode.balanced.subtitle.lowercased().contains("depth"), "preset subtitle should not expose raw depth")
    }

    private static func storageAnalysisBuildsRankedTreeAndCleanupCandidates() throws {
        let root = try makeTemporaryDirectory()
        let derivedData = root.appendingPathComponent("Library/Developer/Xcode/DerivedData/project-a")
        let caches = root.appendingPathComponent("Library/Caches/com.example.cache")
        let downloads = root.appendingPathComponent("Downloads")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try writeBytes(1_200_000, to: derivedData.appendingPathComponent("index.db"))
        try writeBytes(800_000, to: caches.appendingPathComponent("blob.cache"))
        try writeBytes(400_000, to: downloads.appendingPathComponent("archive.zip"))
        try writeBytes(200_000, to: documents.appendingPathComponent("notes.txt"))

        let analysis = StorageService().analysis(
            rootURL: root,
            maxDepth: 5,
            includeHidden: true,
            includeDiskCapacity: false
        )

        try expect(analysis.root.url.standardizedFileURL == root.standardizedFileURL, "analysis root should match requested root")
        try expect(analysis.indexedFileCount == 4, "analysis should index all files")
        try expect(analysis.root.byteCount > 2_000_000, "analysis root should accumulate child sizes")
        try expect(analysis.rankedNodes.first?.url.path.contains("Library") == true, "largest ranked node should come from Library")
        try expect(analysis.cleanupCandidates.contains { $0.url.path.contains("DerivedData") && $0.risk == .safe }, "DerivedData should be a safe cleanup candidate")
        try expect(analysis.cleanupCandidates.contains { $0.url.path.contains("Library/Caches") && $0.risk == .safe }, "Caches should be a safe cleanup candidate")
        try expect(analysis.cleanupCandidates.contains { $0.url.path.contains("Downloads") && $0.risk == .review }, "Downloads should require review")
        try expect(!analysis.cleanupCandidates.contains { $0.url.path.contains("Documents") }, "Documents should not be a cleanup candidate")
        try expect(analysis.scanLog.contains { $0.contains("Indexed 4 files") }, "scan log should include indexed file count")
    }

    private static func slockMetricSampleSummarizesSnapshotAndCapsHistory() throws {
        let root = try makeTemporarySlockRoot()
        let agent = root.appendingPathComponent("agents/agent-a")
        let traces = root.appendingPathComponent("machines/machine-a/traces")
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: traces, withIntermediateDirectories: true)
        try writeBytes(4096, to: agent.appendingPathComponent("workspace.bin"))
        try "trace\n".write(to: traces.appendingPathComponent("one.jsonl"), atomically: true, encoding: .utf8)
        try "trace\n".write(to: traces.appendingPathComponent("two.jsonl"), atomically: true, encoding: .utf8)
        let processOutput = """
        PID ELAPSED %CPU %MEM COMMAND
        42 00:10 1.5 0.4 /usr/local/bin/node /tmp/@slock-ai/daemon
        43 00:12 2.5 0.6 /usr/local/bin/node /tmp/slock-worker
        """

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: processOutput)
        let sample = SlockMetricSample(snapshot: snapshot, sampledAt: Date(timeIntervalSince1970: 10))

        try expect(sample.agentCount == 1, "metric sample should count agents")
        try expect(sample.machineCount == 1, "metric sample should count machines")
        try expect(sample.processCount == 2, "metric sample should count processes")
        try expect(sample.traceCount == 2, "metric sample should count traces")
        try expect(sample.agentCPUPercent == 4.0, "metric sample should sum agent CPU")
        try expect(sample.agentMemoryPercent == 1.0, "metric sample should sum agent memory")
        try expect(sample.agentDiskBytes > 0, "metric sample should include agent disk usage")

        let history = (0..<65).reduce(into: [SlockMetricSample]()) { values, index in
            let next = SlockMetricSample(snapshot: snapshot, sampledAt: Date(timeIntervalSince1970: Double(index)))
            values = SlockMetricSample.appending(next, to: values, limit: 60)
        }
        try expect(history.count == 60, "metric history should keep the last 60 samples")
        try expect(history.first?.sampledAt == Date(timeIntervalSince1970: 5), "metric history should drop oldest samples")
    }

    private static func storagePlaceholderSkipsDiskCapacity() throws {
        let root = try makeTemporaryDirectory()

        let snapshot = StorageService().snapshot(
            homeURL: root,
            includeFolderSizes: false,
            includeDiskCapacity: false
        )

        try expect(snapshot.disk.capacity == 0, "placeholder mode should not query disk capacity")
        try expect(snapshot.disk.available == 0, "placeholder mode should not query disk availability")
        try expect(snapshot.folders.allSatisfy { $0.byteCount == nil }, "placeholder mode should not calculate folder sizes")
    }

    private static func storageEmptySnapshotHasNoWork() throws {
        let snapshot = StorageSnapshot.empty

        try expect(snapshot.disk.capacity == 0, "empty snapshot should not query disk capacity")
        try expect(snapshot.disk.available == 0, "empty snapshot should not query disk availability")
        try expect(snapshot.folders.isEmpty, "empty snapshot should not create folder URLs")
    }

    private static func makeTemporarySlockRoot() throws -> URL {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("machines"), withIntermediateDirectories: true)
        return root
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusMenusTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeBytes(_ count: Int, to url: URL) throws {
        let data = Data(repeating: 0x2A, count: count)
        try data.write(to: url)
    }

    private static func directoryChildren(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            ?? []
    }
}
