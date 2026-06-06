import Foundation

public struct ModuleDescriptor: Identifiable, Equatable {
    public let id: ModuleID
    public let title: String
    public let subtitle: String
    public let symbolName: String
    public let defaultEnabled: Bool

    public init(
        id: ModuleID,
        title: String,
        subtitle: String,
        symbolName: String,
        defaultEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.defaultEnabled = defaultEnabled
    }
}

public enum ModuleRegistry {
    public static let builtIns: [ModuleDescriptor] = [
        ModuleDescriptor(
            id: .storage,
            title: "Storage",
            subtitle: "Space analysis and safe cleanup preview",
            symbolName: "internaldrive"
        ),
        ModuleDescriptor(
            id: .slock,
            title: "Slock Agents",
            subtitle: "Local daemon, agents, and traces",
            symbolName: "person.2"
        ),
        ModuleDescriptor(
            id: .usage,
            title: "Usage Monitor",
            subtitle: "CPU, memory, disk, and processes",
            symbolName: "chart.bar"
        ),
        ModuleDescriptor(
            id: .modules,
            title: "Modules",
            subtitle: "Enable and disable built-in functions",
            symbolName: "square.grid.2x2"
        )
    ]

    public static func descriptor(for id: ModuleID) -> ModuleDescriptor? {
        builtIns.first { $0.id == id }
    }
}
