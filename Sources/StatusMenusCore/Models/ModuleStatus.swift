import Foundation

public enum ModuleStatus: String, Codable, Equatable {
    case healthy
    case warning
    case inactive
    case unavailable
    case loading

    public var label: String {
        switch self {
        case .healthy:
            return "Healthy"
        case .warning:
            return "Warning"
        case .inactive:
            return "Inactive"
        case .unavailable:
            return "Unavailable"
        case .loading:
            return "Loading"
        }
    }
}
