import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case chinese
    case spanish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .spanish: return "Español"
        }
    }
}

enum PawShotColorTheme: String, CaseIterable, Identifiable {
    case rose
    case ocean
    case forest
    case sunset
    case lilac

    var id: String { rawValue }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum Keys {
        static let language = "pawshot.appLanguage"
        static let colorTheme = "pawshot.colorTheme"
    }

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var colorTheme: PawShotColorTheme {
        didSet { UserDefaults.standard.set(colorTheme.rawValue, forKey: Keys.colorTheme) }
    }

    var strings: L10n { L10n(language: language) }
    var palette: ThemePalette { ThemePalette.theme(colorTheme) }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Keys.language), let lang = AppLanguage(rawValue: raw) {
            language = lang
        } else {
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            switch code.prefix(2) {
            case "zh": language = .chinese
            case "es": language = .spanish
            default: language = .english
            }
        }
        if let raw = defaults.string(forKey: Keys.colorTheme), let theme = PawShotColorTheme(rawValue: raw) {
            colorTheme = theme
        } else {
            colorTheme = .rose
        }
    }
}
