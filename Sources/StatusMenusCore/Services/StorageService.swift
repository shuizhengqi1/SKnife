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
    public let byteCount: Int64
    public let isCleanupCandidate: Bool
}

public struct StorageSnapshot: Equatable {
    public let disk: DiskSnapshot
    public let folders: [FolderUsage]
}

public struct StorageService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func snapshot(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> StorageSnapshot {
        let disk = diskSnapshot(for: homeURL)
        let folders = defaultFolders(homeURL: homeURL).map { folder in
            FolderUsage(
                title: folder.title,
                url: folder.url,
                byteCount: directorySize(folder.url),
                isCleanupCandidate: folder.isCleanupCandidate
            )
        }
        .sorted { $0.byteCount > $1.byteCount }

        return StorageSnapshot(disk: disk, folders: folders)
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

    private func directorySize(_ url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else {
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
