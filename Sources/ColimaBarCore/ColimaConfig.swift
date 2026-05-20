import Foundation

public struct ColimaConfig {
    public static let cpuOptions: [Int] = [1, 2, 4, 6, 8]
    public static let memoryOptions: [Int] = [2, 4, 6, 8, 16]

    private static let cpuKey = "colima.desiredCPUs"
    private static let memKey = "colima.desiredMemoryGB"

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
