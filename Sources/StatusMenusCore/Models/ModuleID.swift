import Foundation

public enum ModuleID: String, CaseIterable, Codable, Hashable, Identifiable {
    case storage
    case slock
    case usage
    case modules

    public var id: String { rawValue }
}
