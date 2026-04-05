import SwiftUI

struct ThemePalette: Equatable {
    var primary: Color
    var cream: Color
    var recordYellow: Color
    var tealAccent: Color
    var cardGradientTop: Color
    var cardGradientBottom: Color
    var waveformPlate: Color
    var waveformBarAlt: Color
    var purpleHandle: Color
    var saveGradientTop: Color
    var saveGradientBottom: Color
    var boostOrange: Color
    var sliderTrack: Color
    var cameraAccent: Color

    static func theme(_ id: PawShotColorTheme) -> ThemePalette {
        switch id {
        case .rose:
            return ThemePalette(
                primary: Color(red: 0.365, green: 0.192, blue: 0.224),
                cream: Color(red: 0.99, green: 0.96, blue: 0.96),
                recordYellow: Color(red: 1.0, green: 0.86, blue: 0.15),
                tealAccent: Color(red: 0.15, green: 0.55, blue: 0.58),
                cardGradientTop: Color(red: 0.32, green: 0.12, blue: 0.22),
                cardGradientBottom: Color(red: 0.45, green: 0.22, blue: 0.28),
                waveformPlate: Color(red: 1.0, green: 0.88, blue: 0.90),
                waveformBarAlt: Color(red: 0.98, green: 0.78, blue: 0.82),
                purpleHandle: Color(red: 0.28, green: 0.12, blue: 0.32),
                saveGradientTop: Color(red: 0.42, green: 0.18, blue: 0.28),
                saveGradientBottom: Color(red: 0.32, green: 0.12, blue: 0.22),
                boostOrange: Color(red: 1.0, green: 0.48, blue: 0.12),
                sliderTrack: Color(red: 0.98, green: 0.78, blue: 0.82),
                cameraAccent: Color(red: 0.92, green: 0.35, blue: 0.55)
            )
        case .ocean:
            return ThemePalette(
                primary: Color(red: 0.12, green: 0.38, blue: 0.48),
                cream: Color(red: 0.95, green: 0.98, blue: 0.99),
                recordYellow: Color(red: 1.0, green: 0.86, blue: 0.15),
                tealAccent: Color(red: 0.05, green: 0.62, blue: 0.72),
                cardGradientTop: Color(red: 0.08, green: 0.28, blue: 0.42),
                cardGradientBottom: Color(red: 0.18, green: 0.42, blue: 0.52),
                waveformPlate: Color(red: 0.88, green: 0.95, blue: 0.98),
                waveformBarAlt: Color(red: 0.72, green: 0.88, blue: 0.94),
                purpleHandle: Color(red: 0.1, green: 0.32, blue: 0.45),
                saveGradientTop: Color(red: 0.16, green: 0.45, blue: 0.55),
                saveGradientBottom: Color(red: 0.08, green: 0.32, blue: 0.44),
                boostOrange: Color(red: 1.0, green: 0.48, blue: 0.12),
                sliderTrack: Color(red: 0.75, green: 0.90, blue: 0.95),
                cameraAccent: Color(red: 0.2, green: 0.72, blue: 0.82)
            )
        case .forest:
            return ThemePalette(
                primary: Color(red: 0.20, green: 0.42, blue: 0.32),
                cream: Color(red: 0.97, green: 0.99, blue: 0.96),
                recordYellow: Color(red: 1.0, green: 0.86, blue: 0.15),
                tealAccent: Color(red: 0.22, green: 0.55, blue: 0.42),
                cardGradientTop: Color(red: 0.14, green: 0.32, blue: 0.24),
                cardGradientBottom: Color(red: 0.26, green: 0.48, blue: 0.36),
                waveformPlate: Color(red: 0.90, green: 0.97, blue: 0.92),
                waveformBarAlt: Color(red: 0.78, green: 0.92, blue: 0.84),
                purpleHandle: Color(red: 0.16, green: 0.36, blue: 0.28),
                saveGradientTop: Color(red: 0.28, green: 0.50, blue: 0.38),
                saveGradientBottom: Color(red: 0.16, green: 0.38, blue: 0.30),
                boostOrange: Color(red: 1.0, green: 0.48, blue: 0.12),
                sliderTrack: Color(red: 0.80, green: 0.92, blue: 0.86),
                cameraAccent: Color(red: 0.35, green: 0.78, blue: 0.55)
            )
        case .sunset:
            return ThemePalette(
                primary: Color(red: 0.52, green: 0.28, blue: 0.22),
                cream: Color(red: 0.99, green: 0.97, blue: 0.94),
                recordYellow: Color(red: 1.0, green: 0.86, blue: 0.15),
                tealAccent: Color(red: 0.85, green: 0.42, blue: 0.28),
                cardGradientTop: Color(red: 0.48, green: 0.22, blue: 0.18),
                cardGradientBottom: Color(red: 0.62, green: 0.36, blue: 0.26),
                waveformPlate: Color(red: 1.0, green: 0.92, blue: 0.88),
                waveformBarAlt: Color(red: 0.98, green: 0.78, blue: 0.70),
                purpleHandle: Color(red: 0.45, green: 0.22, blue: 0.18),
                saveGradientTop: Color(red: 0.58, green: 0.30, blue: 0.22),
                saveGradientBottom: Color(red: 0.42, green: 0.20, blue: 0.16),
                boostOrange: Color(red: 1.0, green: 0.48, blue: 0.12),
                sliderTrack: Color(red: 0.98, green: 0.82, blue: 0.74),
                cameraAccent: Color(red: 0.98, green: 0.55, blue: 0.35)
            )
        case .lilac:
            return ThemePalette(
                primary: Color(red: 0.38, green: 0.28, blue: 0.48),
                cream: Color(red: 0.98, green: 0.96, blue: 0.99),
                recordYellow: Color(red: 1.0, green: 0.86, blue: 0.15),
                tealAccent: Color(red: 0.45, green: 0.35, blue: 0.62),
                cardGradientTop: Color(red: 0.30, green: 0.18, blue: 0.42),
                cardGradientBottom: Color(red: 0.44, green: 0.30, blue: 0.52),
                waveformPlate: Color(red: 0.94, green: 0.90, blue: 0.98),
                waveformBarAlt: Color(red: 0.86, green: 0.78, blue: 0.94),
                purpleHandle: Color(red: 0.32, green: 0.20, blue: 0.44),
                saveGradientTop: Color(red: 0.48, green: 0.32, blue: 0.58),
                saveGradientBottom: Color(red: 0.34, green: 0.22, blue: 0.46),
                boostOrange: Color(red: 1.0, green: 0.48, blue: 0.12),
                sliderTrack: Color(red: 0.88, green: 0.80, blue: 0.94),
                cameraAccent: Color(red: 0.72, green: 0.48, blue: 0.88)
            )
        }
    }
}
