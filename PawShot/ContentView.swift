import SwiftUI

enum PawShotMainTab: Hashable {
    case live, gallery, studio, settings
}

struct ContentView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @StateObject private var cameraVM = CameraViewModel()

    @State private var selectedTab: PawShotMainTab = .live
    @State private var highlightAnchors: [Int: HighlightAnchor] = [:]
    @State private var showTutorial = false
    @State private var tutorialStep = 0
    @State private var tutorialHighlightSuppressed = false
    @State private var tutorialHighlightSuppressToken = UUID()
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    private var L: L10n { appSettings.strings }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                CameraTabView(selectedTab: $selectedTab)
                    .tag(PawShotMainTab.live)
                    .tabItem {
                        Label(L.tabLive, systemImage: "video.fill")
                    }

                SessionGalleryView(cameraVM: cameraVM, onDismiss: nil, embedInTab: true)
                    .tag(PawShotMainTab.gallery)
                    .tabItem {
                        Label(L.tabGallery, systemImage: "photo.on.rectangle.angled")
                    }

                SoundLibraryView(soundManager: cameraVM.soundManager, embedInTab: true)
                    .tag(PawShotMainTab.studio)
                    .tabItem {
                        Label(L.tabStudio, systemImage: "sparkles")
                    }

                SettingsView(selectedTab: $selectedTab, showTutorial: $showTutorial)
                    .tag(PawShotMainTab.settings)
                    .tabItem {
                        Label(L.tabSettings, systemImage: "gearshape.fill")
                    }
            }
            .environmentObject(cameraVM)

            if showTutorial {
                TutorialView(
                    anchors: highlightAnchors,
                    isVisible: $showTutorial,
                    currentStep: $tutorialStep,
                    suppressHighlight: tutorialHighlightSuppressed
                )
                .environmentObject(appSettings)
            }
        }
        .onPreferenceChange(HighlightPreferenceKey.self) { highlightAnchors = $0 }
        .onAppear {
            if !hasSeenTutorial {
                showTutorial = true
            }
            refreshSessionForCurrentContext()
        }
        .onChange(of: selectedTab) { _, _ in refreshSessionForCurrentContext() }
        .onChange(of: showTutorial) { wasVisible, visible in
            if visible {
                tutorialStep = 0
                applyTutorialTab(for: tutorialStep, suppressIfTabChanged: true)
            }
            if wasVisible, !visible { hasSeenTutorial = true }
        }
        .onChange(of: tutorialStep) { _, newStep in
            applyTutorialTab(for: newStep, suppressIfTabChanged: true)
        }
    }

    private func tabForTutorialStep(_ step: Int) -> PawShotMainTab {
        switch step {
        case 0...2: return .live
        case 3: return .gallery
        case 4...5: return .studio
        default: return .live
        }
    }

    private func applyTutorialTab(for step: Int, suppressIfTabChanged: Bool) {
        let target = tabForTutorialStep(step)
        if selectedTab != target {
            selectedTab = target
            if suppressIfTabChanged {
                tutorialHighlightSuppressed = true
                let token = UUID()
                tutorialHighlightSuppressToken = token
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard tutorialHighlightSuppressToken == token else { return }
                    tutorialHighlightSuppressed = false
                }
            }
        } else {
            tutorialHighlightSuppressed = false
        }
    }

    private func refreshSessionForCurrentContext() {
        let shouldRun = selectedTab == .live
        if shouldRun {
            cameraVM.startSession()
        } else {
            cameraVM.stopSession()
        }
    }
}

struct CameraTabView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var cameraVM: CameraViewModel
    @Binding var selectedTab: PawShotMainTab

    private var L: L10n { appSettings.strings }
    private var palette: ThemePalette { appSettings.palette }

    @State private var pinchStartZoom: CGFloat = 1.0
    @State private var isPinching = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    if cameraVM.isSessionRunning {
                        CameraPreviewView(session: cameraVM.session)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { scale in
                                        if !isPinching {
                                            isPinching = true
                                            pinchStartZoom = cameraVM.zoomFactor
                                        }
                                        let newZoom = pinchStartZoom * scale
                                        cameraVM.setZoom(newZoom)
                                    }
                                    .onEnded { _ in
                                        isPinching = false
                                        pinchStartZoom = cameraVM.zoomFactor
                                    }
                            )

                            if cameraVM.isAIEnabled && cameraVM.isAIScanning,
                               let face = cameraVM.detectedFace {
                                DogFeaturesHUD(face: face, screenSize: geo.size, lockedLabel: L.faceLocked)
                            }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 60))
                                .foregroundStyle(.gray)
                                .symbolEffect(.pulse)

                            ProgressView()
                                .tint(.white)

                            Text(L.wakingCamera)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.ignoresSafeArea())
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: cameraVM.isSessionRunning)
            }

            VStack {
                topBar
                    .captureRect(0)

                Spacer()

                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                    rightRail
                        .captureRect(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomFloatingControls
                    .captureRect(2)
            }
        }
    }

    private var topBar: some View {
        ZStack(alignment: .center) {
            Text("PawShot")
                .font(.system(size: 26, weight: .bold, design: .default))
                .italic()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                aiToggleButton
                if cameraVM.isAIEnabled && cameraVM.isAIScanning {
                    AIStatusIndicatorView(
                        isLocked: cameraVM.detectedFace != nil,
                        scanningText: L.aiIndicatorScanning,
                        lockedText: L.aiIndicatorLocked
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(.easeInOut(duration: 0.25), value: cameraVM.isAIScanning)
            .animation(.easeInOut(duration: 0.25), value: cameraVM.detectedFace != nil)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }

    private var aiToggleButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            if cameraVM.isAIEnabled {
                cameraVM.isAIEnabled = false
            } else {
                cameraVM.isAIEnabled = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cameraVM.isAIEnabled ? "sparkles" : "sparkles.slash")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22, alignment: .center)
                ZStack {
                    Text(L.aiOn)
                        .font(.caption.weight(.heavy))
                        .lineLimit(1)
                        .frame(width: 54, alignment: .center)
                        .opacity(cameraVM.isAIEnabled ? 1 : 0)
                        .accessibilityHidden(!cameraVM.isAIEnabled)
                    Text(L.aiOff)
                        .font(.caption.weight(.heavy))
                        .lineLimit(1)
                        .frame(width: 54, alignment: .center)
                        .opacity(cameraVM.isAIEnabled ? 0 : 1)
                        .accessibilityHidden(cameraVM.isAIEnabled)
                }
            }
            .foregroundStyle(cameraVM.isAIEnabled ? .white : .white.opacity(0.72))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                cameraVM.isAIEnabled
                    ? Color.cyan.opacity(0.88)
                    : Color.white.opacity(0.12)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .padding(5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var rightRail: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(zoomMaxLabelText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Slider(
                    value: Binding(
                        get: { cameraVM.zoomFactor },
                        set: { cameraVM.setZoom($0) }
                    ),
                    in: 1.0...max(1.01, cameraVM.maxZoomFactor)
                )
                .tint(.yellow)
                .frame(width: 200)
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 200)

                Text(zoomCurrentLabelText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            FlashAttractionShifterView(cameraVM: cameraVM, L: L, palette: palette)
        }
        .padding(.trailing, 10)
        .padding(.bottom, 12)
    }

    /// Room for shutter (94) plus the emergency control sitting above the ring (~114); keeps layout from clipping.
    private let bottomBarControlHeight: CGFloat = 118

    private var bottomFloatingControls: some View {
        HStack(spacing: 0) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                selectedTab = .gallery
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 54, height: 54)
                    if let thumb = cameraVM.lastCapturedThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: bottomBarControlHeight, alignment: .center)
            }
            .buttonStyle(.plain)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                cameraVM.triggerManualSound()
            } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: bottomBarControlHeight, alignment: .center)
            }
            .buttonStyle(.plain)

            ZStack {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    cameraVM.handleShutterPress()
                } label: {
                    ShutterButtonView(
                        isAIEnabled: cameraVM.isAIEnabled,
                        isScanning: cameraVM.isAIScanning,
                        startLabel: L.shutterStart
                    )
                    .frame(width: 94, height: 94)
                }
                .buttonStyle(.plain)

                if cameraVM.isAIEnabled {
                    Button {
                        cameraVM.forceCapture()
                    } label: {
                        EmergencyCaptureButtonLabel()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.a11yEmergencyCapture)
                    // ~2 o’clock on the shutter ring; container sized so the 40pt circle is not clipped
                    .offset(x: 28, y: -34)
                }
            }
            .frame(width: 120, height: 114)
            .frame(maxWidth: .infinity, maxHeight: bottomBarControlHeight, alignment: .center)

            Button {
                cameraVM.switchCamera()
            } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: bottomBarControlHeight, alignment: .center)
            }
            .buttonStyle(.plain)
        }
        .frame(height: bottomBarControlHeight)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var zoomMaxLabelText: String {
        let m = cameraVM.maxZoomFactor
        if m < 1.1 { return "1x" }
        return String(format: "%.0fx", m)
    }

    private var zoomCurrentLabelText: String {
        let z = cameraVM.zoomFactor
        if z < 1.1 { return "1.0x" }
        return String(format: "%.1fx", z)
    }
}

// MARK: - AI status pill (top bar)

private struct AIStatusIndicatorView: View {
    let isLocked: Bool
    let scanningText: String
    let lockedText: String

    var body: some View {
        Text(isLocked ? lockedText : scanningText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                ZStack {
                    if isLocked {
                        Capsule().fill(Color.green.opacity(0.82))
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.45)
                        scanningShimmer
                    }
                }
            }
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(isLocked ? 0.3 : 0.22), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }

    private var scanningShimmer: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            GeometryReader { geo in
                let w = geo.size.width
                let t = context.date.timeIntervalSince1970
                let period = 2.5
                let p = CGFloat((t.truncatingRemainder(dividingBy: period)) / period)
                let sweep = -28 + p * (w + 56)

                LinearGradient(
                    colors: [
                        .white.opacity(0),
                        .white.opacity(0.4),
                        .white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 36, height: geo.size.height)
                .offset(x: sweep)
                .blendMode(.plusLighter)
            }
            .clipShape(Capsule())
        }
    }
}

/// Visual sibling to `ShutterButtonView`’s AI ring — same angular spectrum, dark glass center (not a grey material chip).
private struct EmergencyCaptureButtonLabel: View {
    private static let ringGradient = AngularGradient(
        colors: [.cyan, .blue, .purple, .pink, .orange, .yellow, .cyan],
        center: .center
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.black.opacity(0.55)
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 22
                    )
                )
            Circle()
                .strokeBorder(Self.ringGradient, lineWidth: 2.25)
            Image(systemName: "camera")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .shadow(color: .cyan.opacity(0.4), radius: 6, x: 0, y: 0)
        .shadow(color: .purple.opacity(0.3), radius: 9, x: 0, y: 1)
    }
}

// MARK: - Flash / attraction (long-press menu + tap to choose)

private struct FlashAttractionShifterView: View {
    @ObservedObject var cameraVM: CameraViewModel
    let L: L10n
    let palette: ThemePalette

    /// 上 → 中 → 下：日间、夜间、常亮
    private static let modes: [AttractionMode] = [.day, .night, .constant]
    private let longPressToOpenDuration: TimeInterval = 0.4
    private let tapMaxDistance: CGFloat = 24
    /// 面板向左偏移，布局宽度仍只占闪光键一列，变焦条不挤动
    private let stripOutsetX: CGFloat = 176

    @State private var showStrip = false
    @State private var pressBegan: Date?
    @State private var didOpenStripThisGesture = false

    var body: some View {
        // contentShape + highPriorityGesture 必须只作用在闪光键上；若加在「键 + overlay 菜单」整体上，会优先抢走左侧三档 Button 的点击。
        flashColumn
            .contentShape(Rectangle())
            .highPriorityGesture(flashHoldGesture)
            .overlay(alignment: .leading) {
                if showStrip {
                    shifterStrip
                        .fixedSize(horizontal: true, vertical: true)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: UnitPoint(x: 1, y: 0.5))),
                            removal: .opacity
                        ))
                        .offset(x: -(stripOutsetX))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showStrip)
    }

    private var shifterStrip: some View {
        VStack(spacing: 10) {
            ForEach(Array(Self.modes.enumerated()), id: \.offset) { _, mode in
                modeOptionButton(mode: mode)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.cameraAccent.opacity(0.4), lineWidth: 1)
        )
    }

    private func modeOptionButton(mode: AttractionMode) -> some View {
        let isCurrent = cameraVM.attractionMode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            cameraVM.setAttractionMode(mode, trigger: true)
            showStrip = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: stripOptionIcon(for: mode))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, alignment: .center)
                Text(label(for: mode))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .frame(minWidth: 132)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isCurrent ? palette.recordYellow : palette.cameraAccent.opacity(0.35),
                        lineWidth: isCurrent ? 2.5 : 1
                    )
            )
            .shadow(color: isCurrent ? palette.recordYellow.opacity(0.35) : .clear, radius: 8, y: 0)
        }
        .buttonStyle(.plain)
    }

    private var flashColumn: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                    .shadow(color: palette.cameraAccent.opacity(0.55), radius: 10, y: 0)
                Image(systemName: iconName(for: cameraVM.attractionMode))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(L.flash)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    /// 按住约 0.4s 弹出菜单；短按小位移为即时闪光（常亮模式下为开关手电）；菜单打开时再轻点闪光键区域可关闭
    private var flashHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressBegan == nil {
                    pressBegan = Date()
                }
                guard let t0 = pressBegan, !didOpenStripThisGesture, !showStrip else { return }
                if Date().timeIntervalSince(t0) >= longPressToOpenDuration {
                    didOpenStripThisGesture = true
                    showStrip = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { value in
                let duration = pressBegan.map { Date().timeIntervalSince($0) } ?? 0
                let dist = hypot(value.translation.width, value.translation.height)
                let opened = didOpenStripThisGesture
                pressBegan = nil
                didOpenStripThisGesture = false

                if opened {
                    return
                }

                if showStrip {
                    if duration < 0.45 && dist < tapMaxDistance {
                        showStrip = false
                    }
                    return
                }

                if duration < longPressToOpenDuration, dist <= tapMaxDistance {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    cameraVM.triggerManualFlash()
                }
            }
    }

    private func label(for mode: AttractionMode) -> String {
        switch mode {
        case .day: return L.attractionDay
        case .night: return L.attractionNight
        case .constant: return L.attractionOn
        }
    }

    private func iconName(for mode: AttractionMode) -> String {
        switch mode {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .constant: return cameraVM.isConstantTorchLit ? "flashlight.on.fill" : "flashlight.off.fill"
        }
    }

    /// 弹出条内各档图标固定，不随常亮开关状态变化（主闪光键用 `iconName` 反映开/关）。
    private func stripOptionIcon(for mode: AttractionMode) -> String {
        switch mode {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .constant: return "flashlight.on.fill"
        }
    }
}

struct ShutterButtonView: View {
    let isAIEnabled: Bool
    let isScanning: Bool
    var startLabel: String = "START"

    private let aiGradient = AngularGradient(
        colors: [.cyan, .blue, .purple, .pink, .orange, .yellow, .cyan],
        center: .center
    )

    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    private let outerSize: CGFloat = 92
    private let classicRingLine: CGFloat = 2.5
    private let aiIdleRingLine: CGFloat = 5
    private let aiScanningRingLine: CGFloat = 7

    var body: some View {
        Group {
            if !isAIEnabled {
                classicShutter
            } else if !isScanning {
                aiIdleShutter
            } else {
                aiScanningShutter
            }
        }
        .frame(width: 94, height: 94, alignment: .center)
    }

    /// A. Classic iOS-style shutter: white fill + white stroked outer ring.
    private var classicShutter: some View {
        let inner = outerSize - classicRingLine * 2 - 10
        return ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: classicRingLine)
                .frame(width: outerSize, height: outerSize)
            Circle()
                .fill(Color.white)
                .frame(width: inner, height: inner)
        }
    }

    /// B. AI on, idle: saturated angular gradient ring, white center, black label — no animation.
    private var aiIdleShutter: some View {
        let inner = outerSize - aiIdleRingLine * 2 - 8
        return ZStack {
            Circle()
                .strokeBorder(aiGradient, lineWidth: aiIdleRingLine)
                .frame(width: outerSize, height: outerSize)
            Circle()
                .fill(Color.white)
                .frame(width: inner, height: inner)
            Text(startLabel)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.black)
        }
    }

    /// C. AI scanning: thicker animated gradient ring + stop (rounded square) center.
    private var aiScanningShutter: some View {
        ZStack {
            Circle()
                .strokeBorder(aiGradient, lineWidth: aiScanningRingLine)
                .frame(width: outerSize, height: outerSize)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(pulse)
                .shadow(color: .cyan.opacity(0.45), radius: 8, y: 0)
                .shadow(color: .purple.opacity(0.35), radius: 10, y: 0)
                .onAppear {
                    rotation = 0
                    pulse = 1.0
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                        pulse = 1.05
                    }
                }
                .onDisappear {
                    rotation = 0
                    pulse = 1.0
                }

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
                .frame(width: 26, height: 26)
        }
    }
}

struct DogFeaturesHUD: View {
    let face: DogFaceFeatures
    let screenSize: CGSize
    var lockedLabel: String = "LOCKED"

    var body: some View {
        let width = screenSize.width
        let height = screenSize.height

        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x * width,
                y: (1 - point.y) * height
            )
        }

        let leftEye = convert(face.leftEye)
        let rightEye = convert(face.rightEye)
        let nose = convert(face.nose)

        let color: Color = face.isLookingAtCamera ? .green : .yellow

        return ZStack {
            Path { path in
                path.move(to: leftEye)
                path.addLine(to: rightEye)
                path.addLine(to: nose)
                path.closeSubpath()
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.8), radius: 4)

            Circle().stroke(color, lineWidth: 2).frame(width: 20, height: 20).position(leftEye)
            Circle().stroke(color, lineWidth: 2).frame(width: 20, height: 20).position(rightEye)
            Circle().fill(color).frame(width: 15, height: 15).position(nose)

            if face.isLookingAtCamera {
                Text(lockedLabel)
                    .font(.caption2)
                    .fontWeight(.black)
                    .padding(4)
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .cornerRadius(4)
                    .position(x: nose.x, y: nose.y + 30)
            }
        }
        .animation(.linear(duration: 0.1), value: face.nose)
    }
}
