import Foundation

public enum AppLanguage: String, CaseIterable {
    case system  = "system"
    case french  = "fr"
    case english = "en"
}

public struct L {
    private static let key = "app.language"

    public static var current: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? "system"
            return AppLanguage(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    public static var effective: AppLanguage {
        guard current == .system else { return current }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("fr") ? .french : .english
    }

    public static func t(_ fr: String, _ en: String) -> String {
        effective == .french ? fr : en
    }
}
