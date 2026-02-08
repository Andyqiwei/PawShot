import SwiftUI
import AVFoundation

struct AudioEditorView: View {
    let soundItem: SoundItem
    @ObservedObject var soundManager: SoundManager
    @Environment(\.dismiss) var dismiss
    
    // 波形与时间状态
    @State private var waveformSamples: [Float] = []
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 1
    
    // 播放状态
    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    @State private var isProcessing = false
    
    // 音量状态
    @State private var volume: Float = 1.0
    
    var body: some View {
        VStack {
            Text("编辑音频: \(soundItem.name)")
                .font(.headline)
                .padding(.top)
            
            if duration > 0 {
                // MARK: - 1. 波形编辑区
                VStack {
                    ZStack(alignment: .leading) {
                        // 底层波形
                        WaveformShape(samples: waveformSamples)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 100)
                        
                        // 选中区域高亮
                        GeometryReader { geo in
                            let width = geo.size.width
                            let startX = width * (startTime / duration)
                            let endX = width * (endTime / duration)
                            
                            Rectangle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: endX - startX, height: 100)
                                .offset(x: startX)
                        }
                        .frame(height: 100)
                        
                        // 拖拽手柄
                        GeometryReader { geo in
                            let width = geo.size.width
                            
                            // 左手柄 (Start)
                            DragHandle()
                                .position(x: width * (startTime / duration), y: 50)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let newTime = (value.location.x / width) * duration
                                            startTime = min(max(0, newTime), endTime - 0.2)
                                        }
                                )
                            
                            // 右手柄 (End)
                            DragHandle()
                                .position(x: width * (endTime / duration), y: 50)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let newTime = (value.location.x / width) * duration
                                            endTime = max(min(duration, newTime), startTime + 0.2)
                                        }
                                )
                        }
                        .frame(height: 100)
                    }
                    .padding()
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(10)
                    
                    // 时间显示
                    HStack {
                        Text(formatTime(startTime))
                        Spacer()
                        Text(formatTime(endTime))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
                
                // MARK: - 2. 音量调节区 (150% + 磁吸)
                VStack(spacing: 8) {
                    HStack(spacing: 15) {
                        // 图标
                        Image(systemName: volume > 1.0 ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .foregroundColor(volume > 1.0 ? .orange : .gray)
                        
                        // 滑块
                        Slider(value: $volume, in: 0.0...1.5) // ✅ 最大 150%
                            .accentColor(volume > 1.0 ? .orange : .blue)
                            .onChange(of: volume) { newValue in
                                // ✅ 磁吸逻辑：如果在 1.0 附近 (±3%)，强制吸附
                                if abs(newValue - 1.0) < 0.03 {
                                    if volume != 1.0 {
                                        // 触发轻微震动反馈
                                        let generator = UISelectionFeedbackGenerator()
                                        generator.selectionChanged()
                                        volume = 1.0
                                    }
                                }
                                player?.volume = volume
                            }
                        
                        // 百分比文字
                        Text("\(Int(volume * 100))%")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(volume > 1.0 ? .orange : .primary)
                            .lineLimit(1)       // ✅ 强制单行
                            .minimumScaleFactor(0.8) // 如果字太大允许缩小一点点
                            .frame(width: 50, alignment: .trailing) // ✅ 固定宽度，防止跳动
                    }
                    
                    // 状态提示文字
                    if volume > 1.0 {
                        Text("⚠️ 音量增强 (最大 150%)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .transition(.opacity)
                    } else if volume == 1.0 {
                        Text("标准音量")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .transition(.opacity)
                    } else {
                        Text("音量衰减")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .transition(.opacity)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
            } else {
                ProgressView("正在分析声纹...")
                    .padding()
            }
            
            Spacer()
            
            // MARK: - 3. 控制栏
            HStack(spacing: 40) {
                // 试听按钮
                Button(action: togglePreview) {
                    VStack {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        Text(isPlaying ? "停止" : "试听")
                            .font(.caption)
                    }
                }
                
                // 保存按钮
                Button(action: saveChanges) {
                    VStack {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                        }
                        Text("保存修改")
                            .font(.caption)
                    }
                }
                .disabled(isProcessing)
            }
            .padding(.bottom, 30)
        }
        .onAppear(perform: loadAudioData)
        .onDisappear { stopPreview() }
    }
    
    // MARK: - 逻辑方法
    
    func loadAudioData() {
        self.volume = soundItem.volume
        
        let url: URL
        if soundItem.isSystem {
            url = Bundle.main.url(forResource: soundItem.filename, withExtension: "wav")!
        } else {
            url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(soundItem.filename)
        }
        
        let asset = AVAsset(url: url)
        duration = asset.duration.seconds
        endTime = duration
        
        extractWaveform(from: url)
    }
    
    func extractWaveform(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else { return }
            
            try? file.read(into: buffer)
            
            let frameCount = Int(file.length)
            let samplesPerPoint = frameCount / 100
            guard let channelData = buffer.floatChannelData?[0] else { return }
            
            var points: [Float] = []
            
            if samplesPerPoint > 0 {
                for i in 0..<100 {
                    let start = i * samplesPerPoint
                    if start + samplesPerPoint < frameCount {
                        var sum: Float = 0
                        for j in 0..<samplesPerPoint {
                            let sample = channelData[start + j]
                            sum += sample * sample
                        }
                        points.append(sqrt(sum / Float(samplesPerPoint)))
                    }
                }
            }
            
            if let max = points.max(), max > 0 {
                points = points.map { $0 / max }
            }
            
            DispatchQueue.main.async {
                self.waveformSamples = points
            }
        }
    }
    
    func togglePreview() {
        if isPlaying {
            stopPreview()
        } else {
            playPreview()
        }
    }
    
    func playPreview() {
        let url: URL
        if soundItem.isSystem {
             url = Bundle.main.url(forResource: soundItem.filename, withExtension: "wav")!
        } else {
             url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(soundItem.filename)
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.currentTime = startTime
            player?.volume = volume
            player?.play()
            isPlaying = true
            
            Timer.scheduledTimer(withTimeInterval: endTime - startTime, repeats: false) { _ in
                stopPreview()
            }
        } catch {
            print("播放失败")
        }
    }
    
    func stopPreview() {
        player?.stop()
        isPlaying = false
    }
    
    func saveChanges() {
        isProcessing = true
        stopPreview()
        
        soundManager.updateVolume(for: soundItem.id, newVolume: volume)
        
        let url: URL
        if soundItem.isSystem {
             url = Bundle.main.url(forResource: soundItem.filename, withExtension: "wav")!
        } else {
             url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(soundItem.filename)
        }
        
        let isTimeChanged = (abs(startTime) > 0.1 || abs(endTime - duration) > 0.1)
        
        if isTimeChanged {
            soundManager.trimAudio(sourceURL: url, startTime: startTime, endTime: endTime) { newURL in
                isProcessing = false
                if let newURL = newURL {
                    if !soundItem.isSystem {
                        soundManager.replaceSoundFile(for: soundItem.id, newURL: newURL)
                    } else {
                        let newItem = SoundItem(name: "\(soundItem.name) (剪辑)",
                                                filename: newURL.lastPathComponent,
                                                isSystem: false,
                                                isSelected: true,
                                                volume: volume)
                        soundManager.sounds.append(newItem)
                        soundManager.saveSounds()
                    }
                    dismiss()
                }
            }
        } else {
            isProcessing = false
            dismiss()
        }
    }
    
    func formatTime(_ time: Double) -> String {
        return String(format: "%.1fs", time)
    }
}

// 辅助视图
struct WaveformShape: Shape {
    var samples: [Float]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let count = samples.count
        if count == 0 { return path }
        
        let step = width / CGFloat(count)
        path.move(to: CGPoint(x: 0, y: height / 2))
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * step
            let amplitude = CGFloat(sample) * height / 2
            path.addLine(to: CGPoint(x: x, y: height / 2 - amplitude))
            path.addLine(to: CGPoint(x: x, y: height / 2 + amplitude))
        }
        return path
    }
}

struct DragHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.blue)
            .frame(width: 4, height: 100)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 20, height: 20)
                    .offset(y: -50)
            )
    }
}
