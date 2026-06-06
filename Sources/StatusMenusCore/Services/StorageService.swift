import Foundation

public struct DiskSnapshot: Equatable {
    public let capacity: Int64
    public let available: Int64

    public var used: Int64 {
        max(0, capacity - available)
    }

    public var usedFraction: Double {
        guard capacity > 0 else { return 0 }
        return Double(used) / Double(capacity)
    }
}

public struct FolderUsage: Identifiable, Equatable {
    public var id: String { url.path }
    public let title: String
    public let url: URL
    public let byteCount: Int64?
    public let isCleanupCandidate: Bool
}

public enum StorageCleanupRisk: String, Equatable {
    case safe
    case review
    case protected
}

public struct StorageNode: Identifiable, Equatable {
    public var id: String { url.path }
    public let title: String
    public let url: URL
    public let byteCount: Int64
    public let isDirectory: Bool
    public let risk: StorageCleanupRisk
    public let children: [StorageNode]
}

public struct StorageCleanupCandidate: Identifiable, Equatable {
    public var id: String { url.path }
    public let title: String
    public let url: URL
    public let byteCount: Int64
    public let risk: StorageCleanupRisk
    public let reason: String
}

public struct StorageCleanupResult: Equatable {
    public let url: URL
    public let trashedURL: URL?
    public let succeeded: Bool
    public let message: String
}

public struct StorageAnalysis: Equatable {
    public let disk: DiskSnapshot
    public let root: StorageNode
    public let rankedNodes: [StorageNode]
    public let cleanupCandidates: [StorageCleanupCandidate]
    public let scanLog: [String]
    public let indexedFileCount: Int

    public static let empty = StorageAnalysis(
        disk: DiskSnapshot(capacity: 0, available: 0),
        root: StorageNode(
            title: "No scan",
            url: URL(fileURLWithPath: "/"),
            byteCount: 0,
            isDirectory: true,
            risk: .protected,
            children: []
        ),
        rankedNodes: [],
        cleanupCandidates: [],
        scanLog: [],
        indexedFileCount: 0
    )
}

public struct StorageSnapshot: Equatable {
    public let disk: DiskSnapshot
    public let folders: [FolderUsage]

    public static let empty = StorageSnapshot(
        disk: DiskSnapshot(capacity: 0, available: 0),
        folders: []
    )
}

public struct StorageService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func snapshot(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeFolderSizes: Bool = true,
        includeDiskCapacity: Bool = true
    ) -> StorageSnapshot {
        let disk = includeDiskCapacity
            ? diskSnapshot(for: homeURL)
            : DiskSnapshot(capacity: 0, available: 0)
        let folders = defaultFolders(homeURL: homeURL).map { folder in
            FolderUsage(
                title: folder.title,
                url: folder.url,
                byteCount: includeFolderSizes ? directorySize(folder.url) : nil,
                isCleanupCandidate: folder.isCleanupCandidate
            )
        }
        .sorted { ($0.byteCount ?? -1) > ($1.byteCount ?? -1) }

        return StorageSnapshot(disk: disk, folders: folders)
    }

    public func analysis(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        maxDepth: Int = 3,
        includeHidden: Bool = false,
        includeDiskCapacity: Bool = true
    ) -> StorageAnalysis {
        let root = rootURL.standardizedFileURL
        let disk = includeDiskCapacity ? diskSnapshot(for: root) : DiskSnapshot(capacity: 0, available: 0)
        var indexedFileCount = 0
        let rootNode = scanNode(
            root,
            depth: 0,
            maxDepth: max(0, maxDepth),
            includeHidden: includeHidden,
            indexedFileCount: &indexedFileCount
        ) ?? StorageNode(
            title: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent,
            url: root,
            byteCount: 0,
            isDirectory: true,
            risk: .protected,
            children: []
        )
        let rankedNodes = flattenedNodes(from: rootNode)
            .filter { $0.url.path != rootNode.url.path && $0.byteCount > 0 }
            .sorted {
                if $0.byteCount == $1.byteCount {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.byteCount > $1.byteCount
            }
        let cleanupCandidates = rankedNodes.compactMap(cleanupCandidate)
        let scanLog = [
            "Scanned \(root.path)",
            "Indexed \(indexedFileCount) files",
            "Found \(cleanupCandidates.count) cleanup candidates"
        ]

        return StorageAnalysis(
            disk: disk,
            root: rootNode,
            rankedNodes: rankedNodes,
            cleanupCandidates: cleanupCandidates,
            scanLog: scanLog,
            indexedFileCount: indexedFileCount
        )
    }

    public func moveToTrash(_ candidates: [StorageCleanupCandidate]) -> [StorageCleanupResult] {
        moveURLsToTrash(candidates.map(\.url))
    }

    public func moveURLsToTrash(_ urls: [URL]) -> [StorageCleanupResult] {
        urls.map { url in
            do {
                var trashedURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
                return StorageCleanupResult(
                    url: url,
                    trashedURL: trashedURL as URL?,
                    succeeded: true,
                    message: "Moved to Trash"
                )
            } catch {
                return StorageCleanupResult(
                    url: url,
                    trashedURL: nil,
                    succeeded: false,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func diskSnapshot(for url: URL) -> DiskSnapshot {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else {
            return DiskSnapshot(capacity: 0, available: 0)
        }

        return DiskSnapshot(
            capacity: Int64(values.volumeTotalCapacity ?? 0),
            available: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    private func defaultFolders(homeURL: URL) -> [(title: String, url: URL, isCleanupCandidate: Bool)] {
        [
            ("Downloads", homeURL.appendingPathComponent("Downloads"), true),
            ("Caches", homeURL.appendingPathComponent("Library/Caches"), true),
            ("Trash", homeURL.appendingPathComponent(".Trash"), true),
            ("Documents", homeURL.appendingPathComponent("Documents"), false),
            ("Desktop", homeURL.appendingPathComponent("Desktop"), false)
        ]
    }

    private func scanNode(
        _ url: URL,
        depth: Int,
        maxDepth: Int,
        includeHidden: Bool,
        indexedFileCount: inout Int
    ) -> StorageNode? {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey
              ]),
              values.isSymbolicLink != true
        else {
            return nil
        }

        let title = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let isDirectory = values.isDirectory == true
        guard isDirectory else {
            indexedFileCount += values.isRegularFile == true ? 1 : 0
            return StorageNode(
                title: title,
                url: url,
                byteCount: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                isDirectory: false,
                risk: cleanupRisk(for: url),
                children: []
            )
        }

        guard depth < maxDepth else {
            let summary = directorySummary(url, includeHidden: includeHidden)
            indexedFileCount += summary.fileCount
            return StorageNode(
                title: title,
                url: url,
                byteCount: summary.byteCount,
                isDirectory: true,
                risk: cleanupRisk(for: url),
                children: []
            )
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        let children = ((try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey
            ],
            options: options
        )) ?? [])
            .compactMap {
                scanNode(
                    $0,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    includeHidden: includeHidden,
                    indexedFileCount: &indexedFileCount
                )
            }
            .sorted {
                if $0.byteCount == $1.byteCount {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.byteCount > $1.byteCount
            }

        return StorageNode(
            title: title,
            url: url,
            byteCount: children.reduce(0) { $0 + $1.byteCount },
            isDirectory: true,
            risk: cleanupRisk(for: url),
            children: children
        )
    }

    private func flattenedNodes(from node: StorageNode) -> [StorageNode] {
        [node] + node.children.flatMap(flattenedNodes)
    }

    private func cleanupCandidate(for node: StorageNode) -> StorageCleanupCandidate? {
        guard node.isDirectory, node.byteCount > 0 else {
            return nil
        }

        let components = node.url.pathComponents
        if components.contains("DerivedData") {
            return StorageCleanupCandidate(
                title: node.title,
                url: node.url,
                byteCount: node.byteCount,
                risk: .safe,
                reason: "Xcode DerivedData can usually be regenerated."
            )
        }
        if node.title == "Caches" || components.contains("Caches") {
            return StorageCleanupCandidate(
                title: node.title,
                url: node.url,
                byteCount: node.byteCount,
                risk: .safe,
                reason: "Cache data is usually recreated by apps."
            )
        }
        if node.title == ".Trash" || node.title == "Trash" {
            return StorageCleanupCandidate(
                title: node.title,
                url: node.url,
                byteCount: node.byteCount,
                risk: .safe,
                reason: "Trash contents are already staged for removal."
            )
        }
        if node.title == "Downloads" {
            return StorageCleanupCandidate(
                title: node.title,
                url: node.url,
                byteCount: node.byteCount,
                risk: .review,
                reason: "Downloads can contain important files; review before cleaning."
            )
        }
        return nil
    }

    private func cleanupRisk(for url: URL) -> StorageCleanupRisk {
        let components = url.pathComponents
        if components.contains("DerivedData")
            || components.contains("Caches")
            || components.contains(".Trash")
        {
            return .safe
        }
        if url.lastPathComponent == "Downloads" {
            return .review
        }
        return .protected
    }

    private func directorySize(_ url: URL) -> Int64 {
        directorySummary(url, includeHidden: false).byteCount
    }

    private func directorySummary(_ url: URL, includeHidden: Bool) -> (byteCount: Int64, fileCount: Int) {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard fileManager.fileExists(atPath: url.path),
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
                options: options
              )
        else {
            return (0, 0)
        }

        var total: Int64 = 0
        var fileCount = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .isRegularFileKey
            ]) else {
                continue
            }
            if values.isRegularFile == true {
                fileCount += 1
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return (total, fileCount)
    }
}
