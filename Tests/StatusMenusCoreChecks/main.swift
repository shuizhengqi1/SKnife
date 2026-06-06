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
        try run("Slock discovery scans all directories", discoveryScansAllAgentAndMachineDirectoriesWithoutFixedIDs)
        try run("Slock discovery reports inactive", discoveryReportsInactiveWhenNoSlockStateExists)
        try run("process parser redacts command", parsePSOutputFiltersKeywordsAndRedactsCommand)
        try run("process parser keeps display name", parsePSOutputKeepsDisplayNameWhenCommandIsRedacted)
        try run("byte formatting uses file units", byteFormattingUsesFileStyleUnits)
        try run("percent formatting handles zero total", percentFormattingHandlesZeroTotal)
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

    private static func discoveryReportsInactiveWhenNoSlockStateExists() throws {
        let root = try makeTemporaryDirectory()

        let snapshot = try SlockDiscoveryService().snapshot(rootURL: root, processOutput: "")

        try expect(snapshot.agents.isEmpty, "agents should be empty")
        try expect(snapshot.machines.isEmpty, "machines should be empty")
        try expect(snapshot.status == .inactive, "status should be inactive")
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
}
