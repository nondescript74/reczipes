//
//  AppLanguage.swift
//  Reczipes2
//
//  The language the app is shown in, chosen from the flag in the main toolbar.
//  SwiftUI text follows it at once through the environment's locale (set on the window
//  in Reczipes2App); text built in code reads Bundle.appLanguage. The choice is also
//  written to AppleLanguages, so system-supplied text matches from the next launch.
//  Translations live in Localizable.xcstrings.
//

import SwiftUI

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    static let storageKey = "appLanguage"

    var flag: String {
        switch self {
        case .english: "🇺🇸"
        case .french:  "🇫🇷"
        }
    }

    /// Each language's name in itself, as language pickers show it (never translated).
    var nativeName: String {
        switch self {
        case .english: "English"
        case .french:  "Français"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// The saved choice, or the device language the first time.
    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: saved) {
            return language
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fr") ? .french : .english
    }

    /// The bundle holding this language's strings (falls back to the main bundle).
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    func makeCurrent() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
    }
}

extension Bundle {
    /// Strings built in code use this so they follow the language chosen in the app.
    nonisolated static var appLanguage: Bundle { AppLanguage.current.bundle }
}

/// The flag in the main toolbar: shows the current language, tap to switch.
struct LanguageFlagMenu: View {
    @AppStorage(AppLanguage.storageKey) private var code: String = AppLanguage.current.rawValue

    private var current: AppLanguage { AppLanguage(rawValue: code) ?? .english }

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    language.makeCurrent()
                    code = language.rawValue
                } label: {
                    if language == current {
                        Label { Text(verbatim: "\(language.flag)  \(language.nativeName)") } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: "\(language.flag)  \(language.nativeName)")
                    }
                }
            }
        } label: {
            Text(verbatim: current.flag)
                .font(.title3)
        }
        .menuIndicator(.hidden)
        .help(Text("Language", comment: "Tooltip for the language flag in the toolbar"))
        .accessibilityLabel(Text("Language: \(current.nativeName)", comment: "Accessibility label for the language flag; the argument is the language name"))
    }
}
