import SwiftUI

struct TutorialView: View {
    let anchors: [Int: HighlightAnchor]
    @Binding var isVisible: Bool
    @Binding var currentStep: Int
    var suppressHighlight: Bool
    @EnvironmentObject var appSettings: AppSettingsStore

    private var palette: ThemePalette { appSettings.palette }
    private var L: L10n { appSettings.strings }

    private static let stepKeys: [Int] = [0, 1, 2, 3, 4, 5]
    private let captionGap: CGFloat = 16

    var body: some View {
        Group {
            if isVisible {
                tutorialLayer
            } else {
                EmptyView()
            }
        }
    }

    private var tutorialLayer: some View {
        GeometryReader { geo in
            let globalFrame = geo.frame(in: .global)
            let stepKey = Self.stepKeys[min(currentStep, Self.stepKeys.count - 1)]
            let globalRect = anchors[stepKey]?.rect ?? .zero
            let valid = globalRect.width > 1 && globalRect.height > 1
            let effectiveValid = valid && !suppressHighlight
            let localRect = valid
                ? globalRect.offsetBy(dx: -globalFrame.origin.x, dy: -globalFrame.origin.y)
                : .zero

            let safe = geo.safeAreaInsets
            let size = geo.size
            let placeAbove = captionPlacementAbove(
                rect: localRect,
                valid: effectiveValid,
                size: size,
                safe: safe
            )

            ZStack {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()

                if effectiveValid {
                    highlightBorder(rect: localRect)
                }

                captionRegion(
                    placeAbove: placeAbove,
                    rect: localRect,
                    valid: effectiveValid,
                    size: size,
                    safe: safe
                )
            }
        }
        .ignoresSafeArea()
    }

    private func captionPlacementAbove(rect: CGRect, valid: Bool, size: CGSize, safe: EdgeInsets) -> Bool {
        guard valid else { return true }

        let topInset = safe.top
        let bottomInset = safe.bottom
        let spaceAbove = rect.minY - topInset - captionGap
        let spaceBelow = (size.height - bottomInset - captionGap) - rect.maxY

        if spaceAbove > spaceBelow { return true }
        if spaceBelow > spaceAbove { return false }
        return rect.midY > size.height / 2
    }

    @ViewBuilder
    private func captionRegion(
        placeAbove: Bool,
        rect: CGRect,
        valid: Bool,
        size: CGSize,
        safe: EdgeInsets
    ) -> some View {
        let topInset = safe.top
        let bottomInset = safe.bottom

        if !valid {
            VStack {
                Spacer(minLength: 0)
                captionCard
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        } else if placeAbove {
            VStack(spacing: 0) {
                ZStack {
                    Color.clear
                    captionCard
                        .padding(.horizontal, 16)
                }
                .frame(
                    width: size.width,
                    height: max(72, rect.minY - topInset - captionGap),
                    alignment: .center
                )
                .padding(.top, topInset)

                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    Color.clear
                    captionCard
                        .padding(.horizontal, 16)
                }
                .frame(
                    width: size.width,
                    height: max(72, size.height - bottomInset - rect.maxY - captionGap),
                    alignment: .center
                )
                .padding(.bottom, bottomInset)
            }
        }
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(captionTitle(for: currentStep))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(captionBody(for: currentStep))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary.opacity(0.92))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 12) {
                Button {
                    isVisible = false
                } label: {
                    Text(L.tutorialSkip)
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    advanceStep()
                } label: {
                    Text(currentStep < Self.stepKeys.count - 1 ? L.tutorialNext : L.tutorialDone)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 88)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.recordYellow)
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func captionTitle(for step: Int) -> String {
        switch step {
        case 0: return L.tutorialStep0Title
        case 1: return L.tutorialStep1Title
        case 2: return L.tutorialStep2Title
        case 3: return L.tutorialStep3Title
        case 4: return L.tutorialStep4Title
        default: return L.tutorialStep5Title
        }
    }

    private func captionBody(for step: Int) -> String {
        switch step {
        case 0: return L.tutorialStep0Body
        case 1: return L.tutorialStep1Body
        case 2: return L.tutorialStep2Body
        case 3: return L.tutorialStep3Body
        case 4: return L.tutorialStep4Body
        default: return L.tutorialStep5Body
        }
    }

    private func highlightBorder(rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(palette.recordYellow, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: palette.recordYellow.opacity(0.9), radius: 6, y: 0)
            .shadow(color: palette.recordYellow.opacity(0.5), radius: 16, y: 0)
            .allowsHitTesting(false)
    }

    private func advanceStep() {
        if currentStep < Self.stepKeys.count - 1 {
            currentStep += 1
        } else {
            isVisible = false
        }
    }
}
