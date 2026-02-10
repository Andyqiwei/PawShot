import SwiftUI

struct ContentView: View {
    @StateObject private var cameraVM = CameraViewModel()
    
    @State private var showSoundLibrary = false
    @State private var showSessionGallery = false
    @State private var pinchStartZoom: CGFloat = 1.0
    @State private var isPinching = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. 相机预览层
            GeometryReader { geo in
                ZStack {
                    CameraPreviewView(session: cameraVM.session)
                        .edgesIgnoringSafeArea(.all)
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
                    
                    // MARK: - AI 实时特征点 HUD
                    // 仅当 AI 开启 且 正在扫描 时显示
                    if cameraVM.isAIEnabled && cameraVM.isAIScanning {
                        if let face = cameraVM.detectedFace {
                            DogFeaturesHUD(face: face, screenSize: geo.size)
                        } else {
                            // 扫描中动画
                            VStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("寻找狗狗正脸...")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                }
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(.bottom, 100)
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
            
            VStack {
                // MARK: - 顶部工具栏
                HStack(spacing: 15) {
                    // 左上：诱导模式设置 (Torch Setting)
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        cameraVM.cycleAttractionMode()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: attractionIcon)
                                .font(.title2)
                            Text(attractionText)
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(attractionColor)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    
                    // 中间：AI 开关
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        cameraVM.isAIEnabled.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.title2)
                            if cameraVM.isAIEnabled {
                                Text("AI AUTO")
                                    .font(.caption2)
                                    .fontWeight(.heavy)
                            }
                        }
                        .foregroundColor(cameraVM.isAIEnabled ? .white : .gray)
                        .padding(10)
                        .background(cameraVM.isAIEnabled ? Color.green.opacity(0.8) : Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // 右上：已移除声音设置
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // MARK: - 右侧区域 (变焦 + 诱导)
                HStack(alignment: .bottom) {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        // 1. 变焦
                        VStack(spacing: 6) {
                            Text(zoomLabelText)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Capsule())
                            Slider(
                                value: Binding(
                                    get: { cameraVM.zoomFactor },
                                    set: { cameraVM.setZoom($0) }
                                ),
                                in: 1.0...max(1.01, cameraVM.maxZoomFactor)
                            )
                            .tint(.white)
                            .frame(width: 28, height: 140)
                            .rotationEffect(.degrees(-90))
                        }
                        .padding(.bottom, 10)
                        
                        // 2. 手动闪光 (执行左上角设定的模式)
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            cameraVM.triggerManualFlash()
                        }) {
                            Image(systemName: "flashlight.on.fill")
                                .font(.title2)
                                .foregroundColor(cameraVM.attractionMode == .constant ? .yellow : .white)
                                .padding(14)
                                .background(Color.gray.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // 3. 手动声音
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            cameraVM.triggerManualSound()
                        }) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Color.blue.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 20)
                }
                .frame(maxHeight: .infinity)
                
                // MARK: - 底部操作栏
                HStack(spacing: 16) {
                    // 相册
                    Button(action: { showSessionGallery = true }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 56, height: 56)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.5), lineWidth: 1))
                            if let thumb = cameraVM.lastCapturedThumbnail {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    
                    // 声音库
                    Button(action: { showSoundLibrary = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.largeTitle)
                            Text("Sounds")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                    }
                    .frame(width: 80)
                    
                    Spacer()
                    
                    // 📸 主快门
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        cameraVM.handleShutterPress()
                    }) {
                        ShutterButtonView(
                            isAIEnabled: cameraVM.isAIEnabled,
                            isScanning: cameraVM.isAIScanning
                        )
                    }
                    
                    Spacer()
                    
                    // 翻转
                    Button(action: { cameraVM.switchCamera() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.rotate.fill")
                                .font(.largeTitle)
                            Text("Flip")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.trailing, 30)
                    .frame(width: 80)
                }
                .padding(.leading, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear { cameraVM.startSession() }
        // 4. 生命周期的改进：打开相册/声音库时停止 Session，回来时启动
        .onChange(of: showSessionGallery) { isOpen in
            if isOpen { cameraVM.stopSession() }
            else { cameraVM.startSession() }
        }
        .onChange(of: showSoundLibrary) { isOpen in
            if isOpen { cameraVM.stopSession() }
            else { cameraVM.startSession() }
        }
        .sheet(isPresented: $showSoundLibrary) {
            SoundLibraryView(soundManager: cameraVM.soundManager)
        }
        .sheet(isPresented: $showSessionGallery) {
            SessionGalleryView(cameraVM: cameraVM, onDismiss: { showSessionGallery = false })
        }
    }
    
    // 辅助计算属性
    var attractionIcon: String {
        switch cameraVM.attractionMode {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .constant: return "flashlight.on.fill"
        }
    }
    
    var attractionColor: Color {
        switch cameraVM.attractionMode {
        case .day: return .white
        case .night: return .yellow
        case .constant: return .orange
        }
    }
    
    var attractionText: String {
        switch cameraVM.attractionMode {
        case .day: return "DAY"
        case .night: return "NIGHT"
        case .constant: return "ON"
        }
    }
    
    var zoomLabelText: String {
        let z = cameraVM.zoomFactor
        if z < 1.1 { return "1x" }
        return String(format: "%.1fx", z)
    }
}

// 独立的快门样式组件
struct ShutterButtonView: View {
    let isAIEnabled: Bool
    let isScanning: Bool
    
    var body: some View {
        ZStack {
            if isAIEnabled {
                // AI 模式
                if isScanning {
                    // 扫描中：红色停止键
                    Circle()
                        .fill(Color.red)
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(Color.red, lineWidth: 4)
                        .frame(width: 80, height: 80)
                } else {
                    // 待机中：绿色开始键
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                    Text("START")
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundColor(.black)
                    Circle()
                        .stroke(Color.green, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }
            } else {
                // 普通模式：白色拍照键
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
            }
        }
    }
}

// 保持 HUD 不变
struct DogFeaturesHUD: View {
    let face: DogFaceFeatures
    let screenSize: CGSize
    
    var body: some View {
        let width = screenSize.width
        let height = screenSize.height
        
        func convert(_ point: CGPoint) -> CGPoint {
            return CGPoint(
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
                Text("LOCKED")
                    .font(.caption2)
                    .fontWeight(.black)
                    .padding(4)
                    .background(Color.green)
                    .foregroundColor(.black)
                    .cornerRadius(4)
                    .position(x: nose.x, y: nose.y + 30)
            }
        }
        .animation(.linear(duration: 0.1), value: face.nose)
    }
}
