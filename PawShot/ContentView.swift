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
                TutorialView(anchors: highlightAnchors, isVisible: $showTutorial)
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
            if wasVisible, !visible { hasSeenTutorial = true }
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

                            if cameraVM.isAIEnabled && cameraVM.isAIScanning {
                                if let face = cameraVM.detectedFace {
                                    DogFeaturesHUD(face: face, screenSize: geo.size, lockedLabel: L.faceLocked)
                                } else {
                                    VStack {
                                        Spacer()
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .tint(.white)
                                            Text(L.scanningForDog)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundStyle(.white)
                                        }
                                        .padding(12)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                        .padding(.bottom, 100)
                                    }
                                    .transition(.opacity)
                                }
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

                HStack(alignment: .bottom) {
                    Spacer()
                    rightRail
                        .captureRect(1)
                }
                .frame(maxHeight: .infinity)

                bottomFloatingControls
                    .captureRect(2)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("PawShot")
                .font(.system(size: 26, weight: .bold, design: .default))
                .italic()
                .foregroundStyle(.white)

            Spacer(minLength: 8)

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
                    Text(L.aiAuto)
                        .font(.caption.weight(.heavy))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
        .padding(.top, 12)
        .padding(.horizontal, 16)
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
            }
            .buttonStyle(.plain)

            Spacer()

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
            }
            .buttonStyle(.plain)

            Spacer()

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
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                cameraVM.switchCamera()
            } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
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

    @State private var haloBreath = false

    private var intelligenceSpectrum: [Color] {
        [
            Color(red: 0.45, green: 0.28, blue: 0.98),
            Color(red: 0.22, green: 0.48, blue: 1.0),
            Color(red: 0.18, green: 0.78, blue: 0.98),
            Color(red: 0.28, green: 0.92, blue: 0.58),
            Color(red: 0.98, green: 0.82, blue: 0.22),
            Color(red: 0.98, green: 0.32, blue: 0.52),
            Color(red: 0.62, green: 0.38, blue: 0.98),
            Color(red: 0.45, green: 0.28, blue: 0.98),
        ]
    }

    var body: some View {
        Group {
            if isAIEnabled {
                aiShutter
            } else {
                manualShutter
            }
        }
    }

    private var aiShutter: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 5)
                .frame(width: 92, height: 92)
                .scaleEffect(haloBreath ? 1.06 : 0.97)
                .opacity(haloBreath ? 0.55 : 0.2)

            TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let spin = (t.truncatingRemainder(dividingBy: 4.8)) / 4.8 * 360.0
                let breath = 1.0 + 0.05 * sin(t * (2 * .pi / 2.15))
                let cx = 0.5 + 0.42 * cos(t * 1.05)
                let cy = 0.5 + 0.42 * sin(t * 1.05)

                ZStack {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: intelligenceSpectrum,
                                startPoint: UnitPoint(x: cx, y: cy),
                                endPoint: UnitPoint(x: 1 - cx, y: 1 - cy)
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 88, height: 88)
                        .blur(radius: 1.8)
                        .opacity(0.72)
                        .rotationEffect(.degrees(spin))
                        .scaleEffect(breath)

                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: intelligenceSpectrum,
                                startPoint: UnitPoint(x: 1 - cx, y: cy),
                                endPoint: UnitPoint(x: cx, y: 1 - cy)
                            ),
                            lineWidth: 2.8
                        )
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(spin))
                        .scaleEffect(breath)
                }
            }

            Circle()
                .fill(Color.black.opacity(0.92))
                .frame(width: 68, height: 68)

            aiCenterContent
        }
        .frame(width: 94, height: 94)
        .onAppear {
            haloBreath = false
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                haloBreath = true
            }
        }
    }

    @ViewBuilder
    private var aiCenterContent: some View {
        if isScanning {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 26, height: 26)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white)
                    .frame(width: 22, height: 22)
            }
        } else {
            Text(startLabel)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
        }
    }

    private var manualShutter: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                .frame(width: 86, height: 86)
            Circle()
                .strokeBorder(Color.gray.opacity(0.45), lineWidth: 1)
                .frame(width: 78, height: 78)
            Circle()
                .fill(Color.white)
                .frame(width: 68, height: 68)

            Image(systemName: "camera.aperture")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))
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
