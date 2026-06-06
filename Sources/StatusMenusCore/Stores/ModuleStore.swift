import Combine
import Foundation

@MainActor
public final class ModuleStore: ObservableObject {
    public static let defaultRefreshInterval: Double = 5
    public static let minimumRefreshInterval: Double = 1

    @Published public var selectedModule: ModuleID
    @Published public var refreshInterval: Double {
        didSet { userDefaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }
    @Published public var slockRootPath: String {
        didSet { userDefaults.set(slockRootPath, forKey: Keys.slockRootPath) }
    }

    private let userDefaults: UserDefaults
    private var disabledModuleIDs: Set<ModuleID>

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.selectedModule = .storage
        self.refreshInterval = userDefaults.object(forKey: Keys.refreshInterval) as? Double ?? Self.defaultRefreshInterval
        self.slockRootPath = userDefaults.string(forKey: Keys.slockRootPath)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".slock").path

        let rawDisabled = userDefaults.stringArray(forKey: Keys.disabledModules) ?? []
        self.disabledModuleIDs = Set(rawDisabled.compactMap(ModuleID.init(rawValue:)))
        self.disabledModuleIDs.remove(.modules)
    }

    public var enabledDescriptors: [ModuleDescriptor] {
        ModuleRegistry.builtIns.filter { isEnabled($0.id) }
    }

    public var effectiveRefreshInterval: Double {
        max(Self.minimumRefreshInterval, refreshInterval)
    }

    public func isEnabled(_ moduleID: ModuleID) -> Bool {
        if moduleID == .modules {
            return true
        }
        guard let descriptor = ModuleRegistry.descriptor(for: moduleID) else {
            return false
        }
        return descriptor.defaultEnabled && !disabledModuleIDs.contains(moduleID)
    }

    public func setEnabled(_ enabled: Bool, for moduleID: ModuleID) {
        guard moduleID != .modules else {
            disabledModuleIDs.remove(.modules)
            persistDisabledModules()
            return
        }

        if enabled {
            disabledModuleIDs.remove(moduleID)
        } else {
            disabledModuleIDs.insert(moduleID)
        }
        persistDisabledModules()
    }

    private func persistDisabledModules() {
        let rawIDs = disabledModuleIDs.map(\.rawValue).sorted()
        userDefaults.set(rawIDs, forKey: Keys.disabledModules)
    }

    private enum Keys {
        static let disabledModules = "StatusMenus.disabledModules"
        static let refreshInterval = "StatusMenus.refreshInterval"
        static let slockRootPath = "StatusMenus.slockRootPath"
    }
}
