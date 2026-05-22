import Foundation

public struct ColimaConfig {
    public static let cpuOptions:    [Int] = [1, 2, 4, 6, 8]
    public static let memoryOptions: [Int] = [2, 4, 6, 8, 16]
    public static let diskOptions:   [Int] = [20, 40, 60, 100, 200]

    private static let cpuKey          = "colima.desiredCPUs"
    private static let memKey          = "colima.desiredMemoryGB"
    private static let diskKey         = "colima.desiredDiskGB"
    private static let autoStartKey    = "colima.autoStartOnLaunch"
    private static let showAllKey      = "colima.showAllContainers"
    private static let instanceKey     = "colima.activeInstanceName"
    private static let pollingKey      = "colima.pollingPreset"
    private static let compactModeKey  = "colima.compactMode"

    public static var autoStartOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: autoStartKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoStartKey) }
    }

    public static var showAllContainers: Bool {
        get {
            let v = UserDefaults.standard.object(forKey: showAllKey)
            return v == nil ? true : UserDefaults.standard.bool(forKey: showAllKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showAllKey) }
    }

    public static var desiredCPUs: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: cpuKey)
            return v > 0 ? v : 2
        }
        set { UserDefaults.standard.set(newValue, forKey: cpuKey) }
    }

    public static var desiredMemoryGB: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: memKey)
            return v > 0 ? v : 4
        }
        set { UserDefaults.standard.set(newValue, forKey: memKey) }
    }

    public static var desiredDiskGB: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: diskKey)
            return v > 0 ? v : 60
        }
        set { UserDefaults.standard.set(newValue, forKey: diskKey) }
    }

    public static var activeInstanceName: String {
        get { UserDefaults.standard.string(forKey: instanceKey) ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: instanceKey) }
    }

    public static var pollingPreset: PollingPreset {
        get {
            let raw = UserDefaults.standard.string(forKey: pollingKey) ?? ""
            return PollingPreset(rawValue: raw) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: pollingKey) }
    }

    public static var compactModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: compactModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: compactModeKey) }
    }
}

public struct ColimaProfile: Equatable {
    public let name: String
    public let nameFR: String
    public let cpus: Int
    public let memoryGB: Int

    public static let presets: [ColimaProfile] = [
        ColimaProfile(name: "Minimal", nameFR: "Minimal", cpus: 1, memoryGB: 2),
        ColimaProfile(name: "Dev",     nameFR: "Dev",     cpus: 2, memoryGB: 4),
        ColimaProfile(name: "Heavy",   nameFR: "Intense", cpus: 4, memoryGB: 8),
    ]
}

public enum PollingPreset: String, CaseIterable {
    case fast   = "fast"   // 2s running / 10s stopped
    case normal = "normal" // 5s running / 30s stopped (default)
    case slow   = "slow"   // 15s running / 60s stopped

    public var runningInterval: TimeInterval {
        switch self { case .fast: return 2; case .normal: return 5; case .slow: return 15 }
    }
    public var stoppedInterval: TimeInterval {
        switch self { case .fast: return 10; case .normal: return 30; case .slow: return 60 }
    }
    public var label: String {
        switch self {
        case .fast:   return L.t("Rapide", "Fast")
        case .normal: return L.t("Normal", "Normal")
        case .slow:   return L.t("Lent", "Slow")
        }
    }
}
