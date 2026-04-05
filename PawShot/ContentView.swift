import SwiftUI

enum PawShotMainTab: Hashable {
    case live, gallery, studio, settings
}

struct ContentView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @StateObject private var cameraVM = CameraViewModel()

    @State private var selectedTab: PawShotMainTab = .live

    private var L: L10n { appSettings.strings }

    var body: some View {
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

            SettingsView()
                .tag(PawShotMainTab.settings)
                .tabItem {
                    Label(L.tabSettings, systemImage: "gearshape.fill")
                }
        }
        .environmentObject(cameraVM)
        .onAppear(perform: refreshSessionForCurrentContext)
        .onChange(of: selectedTab) { _, _ in refreshSessionForCurrentContext() }
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

            HStack(spacing: 8) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    cameraVM.isAIEnabled.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.body.weight(.semibold))
                        Text(L.aiAuto)
                            .font(.caption.weight(.heavy))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        cameraVM.isAIEnabled
                            ? Color.cyan.opacity(0.88)
                            : Color.clear
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    cameraVM.cycleAttractionMode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: attractionIcon)
                            .font(.body.weight(.semibold))
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.attraction)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(attractionLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
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

            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                cameraVM.triggerManualFlash()
            } label: {
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                            .shadow(color: palette.cameraAccent.opacity(0.55), radius: 10, y: 0)
                        Image(systemName: "bolt.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Text(L.flash)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
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

    private var attractionIcon: String {
        switch cameraVM.attractionMode {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .constant: return "flashlight.on.fill"
        }
    }

    private var attractionLabel: String {
        switch cameraVM.attractionMode {
        case .day: return L.attractionDay
        case .night: return L.attractionNight
        case .constant: return L.attractionOn
        }
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

struct ShutterButtonView: View {
    let isAIEnabled: Bool
    let isScanning: Bool
    var startLabel: String = "START"

    private let yellowFill = Color(red: 1, green: 0.86, blue: 0.15)

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                .frame(width: 86, height: 86)
            Circle()
                .strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
                .frame(width: 76, height: 76)

            Circle()
                .fill(yellowFill)
                .frame(width: 68, height: 68)

            if isAIEnabled {
                if isScanning {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black.opacity(0.88))
                        .frame(width: 26, height: 26)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 22, height: 22)
                } else {
                    Text(startLabel)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black)
                }
            } else {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
            }
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
