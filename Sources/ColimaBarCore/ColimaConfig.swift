import Foundation

public struct ColimaConfig {
    public static let cpuOptions: [Int] = [1, 2, 4, 6, 8]
    public static let memoryOptions: [Int] = [2, 4, 6, 8, 16]

    private static let cpuKey          = "colima.desiredCPUs"
    private static let memKey          = "colima.desiredMemoryGB"
    private static let autoStartKey    = "colima.autoStartOnLaunch"
    private static let showAllKey      = "colima.showAllContainers"

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
