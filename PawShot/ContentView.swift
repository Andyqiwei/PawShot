import SwiftUI

struct ContentView: View {
    // 初始化相机逻辑核心
    @StateObject private var cameraVM = CameraViewModel()
    
    // ✅ 新增状态：控制是否显示声音库
    @State private var showSoundLibrary = false
    // 变焦捏合：手势开始时记录的变焦值
    @State private var pinchStartZoom: CGFloat = 1.0
    @State private var isPinching = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. 相机预览层 (始终显示) + 捏合变焦
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
            
            VStack {
                // MARK: - 顶部工具栏 (闪光灯模式 + 音效开关)
                HStack {
                    // 💡 灯光模式切换
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        cameraVM.cycleLightingMode()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: lightingIconName)
                                .font(.title2)
                            Text(lightingText)
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(lightingColor)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // 🔊 总音效开关 (静音/开启)
                    Button(action: { cameraVM.isSoundEnabled.toggle() }) {
                        Image(systemName: cameraVM.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.title2)
                            .foregroundColor(cameraVM.isSoundEnabled ? .yellow : .white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // MARK: - 右侧变焦滑块
                HStack {
                    Spacer()
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
                    .padding(.trailing, 12)
                }
                .frame(maxHeight: .infinity)
                
                // MARK: - 底部操作栏 (声音库 | 快门 | 翻转)
                HStack {
                    
                    // 🎵 左侧：声音库入口
                    Button(action: {
                        showSoundLibrary = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.largeTitle)
                            Text("Sounds")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.leading, 30)
                    .frame(width: 80) // 固定宽度保持布局平衡
                    
                    Spacer()
                    
                    // 📸 中间：巨大的快门按钮
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        cameraVM.takePhoto()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 72, height: 72)
                            Circle()
                                .stroke(Color.gray, lineWidth: 4)
                                .frame(width: 80, height: 80)
                        }
                    }
                    
                    Spacer()
                    
                    // 🔄 右侧：翻转摄像头
                    Button(action: {
                        // 触发翻转逻辑
                        // 注意：如果你的 CameraViewModel 还没加 switchCamera，记得加上（代码在下面）
                         cameraVM.switchCamera()
                    }) {
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
                    .frame(width: 80) // 固定宽度保持布局平衡
                }
                .padding(.bottom, 40)
            }
        }
        // 生命周期控制
        .onAppear { cameraVM.startSession() }
        .onDisappear { cameraVM.stopSession() }
        
        // ✅ 弹窗：声音库界面
        .sheet(isPresented: $showSoundLibrary) {
            // 将 ViewModel 里的管理器传给 UI
            SoundLibraryView(soundManager: cameraVM.soundManager)
        }
    }
    
    // MARK: - 辅助计算属性 (保持代码整洁)
    
    var lightingIconName: String {
        switch cameraVM.lightingMode {
        case .off: return "bolt.slash.fill"
        case .constant: return "flashlight.on.fill"
        case .strobeLightOn: return "bolt.badge.a.fill"
        case .strobeLightOff: return "bolt.slash.circle.fill"
        }
    }
    
    var lightingColor: Color {
        switch cameraVM.lightingMode {
        case .off: return .white
        case .constant: return .yellow
        case .strobeLightOn: return .orange
        case .strobeLightOff: return .green
        }
    }
    
    var lightingText: String {
        switch cameraVM.lightingMode {
        case .off: return "OFF"
        case .constant: return "TORCH"
        case .strobeLightOn: return "NIGHT"
        case .strobeLightOff: return "DAY"
        }
    }
    
    /// 变焦倍数显示文案（如 "1x" / "2.5x"）
    var zoomLabelText: String {
        let z = cameraVM.zoomFactor
        if z < 1.1 { return "1x" }
        return String(format: "%.1fx", z)
    }
}
