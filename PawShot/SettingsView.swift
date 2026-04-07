import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Binding var selectedTab: PawShotMainTab
    @Binding var showTutorial: Bool
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    private var L: L10n { appSettings.strings }
    private var palette: ThemePalette { appSettings.palette }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.cream.ignoresSafeArea()

                List {
                    Section {
                        NavigationLink {
                            LanguagePickerSheetContent()
                                .environmentObject(appSettings)
                        } label: {
                            settingsRow(
                                icon: "globe",
                                iconTint: palette.tealAccent,
                                title: L.settingsLanguage,
                                value: appSettings.language.displayName
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        NavigationLink {
                            ColorThemePickerContent()
                                .environmentObject(appSettings)
                        } label: {
                            settingsRow(
                                icon: "paintpalette.fill",
                                iconTint: palette.cameraAccent,
                                title: L.settingsColorTheme,
                                value: appSettings.strings.themeName(appSettings.colorTheme)
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        Button {
                            hasSeenTutorial = false
                            selectedTab = .live
                            showTutorial = true
                        } label: {
                            settingsReplayRow
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        Text(L.settingsFooter)
                            .font(.footnote)
                            .foregroundStyle(palette.primary.opacity(0.55))
                            .padding(.vertical, 4)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 16, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .tint(palette.primary)
            .toolbarBackground(palette.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var settingsReplayRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(palette.cameraAccent.opacity(0.22))
                    .frame(width: 48, height: 48)
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.cameraAccent)
            }

            Text(L.tutorialReplay)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: palette.primary.opacity(0.08), radius: 10, y: 4)
        )
    }

    private func settingsRow(icon: String, iconTint: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.22))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.primary.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: palette.primary.opacity(0.08), radius: 10, y: 4)
        )
    }
}

// MARK: - Sub-pages (same visual language as main settings list)

private struct LanguagePickerSheetContent: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    private var L: L10n { appSettings.strings }
    private var palette: ThemePalette { appSettings.palette }

    var body: some View {
        ZStack {
            palette.cream.ignoresSafeArea()

            List {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        appSettings.language = lang
                    } label: {
                        HStack(spacing: 14) {
                            Text(lang.displayName)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.primary)
                            Spacer(minLength: 0)
                            if appSettings.language == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(palette.tealAccent)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                                .shadow(color: palette.primary.opacity(0.08), radius: 10, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L.settingsLanguage)
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.primary)
        .toolbarBackground(palette.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct ColorThemePickerContent: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    private var L: L10n { appSettings.strings }
    private var palette: ThemePalette { appSettings.palette }

    var body: some View {
        ZStack {
            palette.cream.ignoresSafeArea()

            List {
                ForEach(PawShotColorTheme.allCases) { theme in
                    Button {
                        appSettings.colorTheme = theme
                    } label: {
                        HStack(spacing: 14) {
                            themeSwatch(for: theme)

                            Text(L.themeName(theme))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.primary)

                            Spacer(minLength: 0)

                            if appSettings.colorTheme == theme {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(palette.tealAccent)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                                .shadow(color: palette.primary.opacity(0.08), radius: 10, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L.settingsColorTheme)
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.primary)
        .toolbarBackground(palette.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func themeSwatch(for theme: PawShotColorTheme) -> some View {
        let p = ThemePalette.theme(theme)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [p.cardGradientTop, p.cardGradientBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: p.primary.opacity(0.25), radius: 4, y: 2)
    }
}
