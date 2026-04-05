import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(appSettings.strings.settingsLanguage, selection: $appSettings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker(appSettings.strings.settingsColorTheme, selection: $appSettings.colorTheme) {
                        ForEach(PawShotColorTheme.allCases) { theme in
                            Text(appSettings.strings.themeName(theme)).tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text(appSettings.strings.settingsFooter)
                        .font(.footnote)
                }
            }
            .navigationTitle(appSettings.strings.settingsTitle)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
