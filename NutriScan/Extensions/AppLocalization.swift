import SwiftUI

enum AppLocalization {
    static let languageStorageKey = "nutriscan.app_language"

    static var currentLocale: Locale {
        selectedLocale ?? .autoupdatingCurrent
    }

    static var selectedLocale: Locale? {
        let rawValue = UserDefaults.standard.string(forKey: languageStorageKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: rawValue) ?? .system
        return language.locale
    }

    static func current(_ key: String) -> String {
        localized(key, locale: selectedLocale)
    }

    static func currentFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: current(key), locale: currentLocale, arguments: arguments)
    }

    static func localized(_ key: String, locale: Locale?) -> String {
        if let locale,
           let languageCode = languageCode(for: locale),
           let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return String(localized: String.LocalizationValue(key))
    }

    static func localized(_ key: String, locale: Locale) -> String {
        localized(key, locale: Optional(locale))
    }

    static func formatted(_ key: String, locale: Locale, _ arguments: [CVarArg]) -> String {
        String(format: localized(key, locale: locale), locale: locale, arguments: arguments)
    }

    private static func languageCode(for locale: Locale) -> String? {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if identifier.hasPrefix("zh-Hans") {
            return "zh-Hans"
        }
        return identifier.split(separator: "-").first.map(String.init)
    }
}
