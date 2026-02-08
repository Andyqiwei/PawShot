import Foundation
import AVFoundation
import SwiftUI // 必须引入，否则无法使用 remove(atOffsets:)
import Combine

struct SoundItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var filename: String
    var isSystem: Bool
    var isSelected: Bool
    var volume: Float = 1.0
}

class SoundManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    
    @Published var sounds: [SoundItem] = []
    @Published var isRecording = false
    @Published var permissionGranted = false // ✅ 新增：标记是否有权限
    
    private var audioRecorder: AVAudioRecorder?
    
    // 路径定义
    private var documentsPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var listSavePath: URL {
        documentsPath.appendingPathComponent("sound_list.json")
    }
    
    override init() {
        super.init()
        loadSounds()
        checkPermission() // ✅ 初始化时检查权限
    }
    
    // MARK: - 权限检查
    func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            permissionGranted = true
        case .denied:
            permissionGranted = false
        case .undetermined:
            // 如果还没决定，先不置可否，等用户点录音时再请求
            permissionGranted = false
        @unknown default:
            permissionGranted = false
        }
    }
    
    // MARK: - 播放逻辑
    func getRandomPlayableSound() -> (URL, Float)? {
        let activeSounds = sounds.filter { $0.isSelected }
        guard let item = activeSounds.randomElement() else {
            if let defaultUrl = Bundle.main.url(forResource: "squeak", withExtension: "wav") {
                return (defaultUrl, 1.0)
            }
            return nil
        }
        
        let url: URL
        if item.isSystem {
            url = Bundle.main.url(forResource: item.filename, withExtension: "wav") ?? documentsPath
        } else {
            url = documentsPath.appendingPathComponent(item.filename)
        }
        return (url, item.volume)
    }
    
    // MARK: - 数据持久化
    func loadSounds() {
        if let data = try? Data(contentsOf: listSavePath),
           let savedSounds = try? JSONDecoder().decode([SoundItem].self, from: data) {
            self.sounds = savedSounds
        } else {
            self.sounds = [
                SoundItem(name: "Squeaky Toy", filename: "squeak", isSystem: true, isSelected: true)
            ]
            saveSounds()
        }
    }
    
    func saveSounds() {
        if let data = try? JSONEncoder().encode(sounds) {
            try? data.write(to: listSavePath)
        }
    }
    
    func toggleSelection(for item: SoundItem) {
        if let index = sounds.firstIndex(where: { $0.id == item.id }) {
            sounds[index].isSelected.toggle()
            saveSounds()
        }
    }
    
    func deleteSound(at offsets: IndexSet) {
        sounds.remove(atOffsets: offsets)
        saveSounds()
    }
    
    // MARK: - 录音功能 (修复版)
    private var currentRecordingName: String = ""
    
    // ✅ 修复版：强制请求权限
    func startRec() {
        let session = AVAudioSession.sharedInstance()
        
        // 1. 如果权限还没决定，或者被拒绝，再次请求
        if session.recordPermission != .granted {
            print("⚠️ 权限未获取，正在请求...")
            session.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    self.permissionGranted = allowed
                    if allowed {
                        print("✅ 权限已获取，重新尝试录音")
                        self.startRec() // 递归调用：拿到权限后立刻开始
                    } else {
                        print("❌ 用户拒绝了麦克风权限")
                        // 这里可以加一个弹窗提示用户去设置里打开
                    }
                }
            }
            return
        }
        
        // 2. 如果已有权限，开始录音配置
        let filename = "rec_\(Int(Date().timeIntervalSince1970)).m4a"
        self.currentRecordingName = filename
        let path = documentsPath.appendingPathComponent(filename)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: path, settings: settings)
            audioRecorder?.record()
            isRecording = true
            print("🎙️ 开始录音: \(path.lastPathComponent)")
        } catch {
            print("❌ 录音启动失败: \(error)")
            isRecording = false
        }
    }
    
    // MARK: - 录音控制 (修复版)
        
    // 1. 立即停止硬件录音 (绑定到红色停止按钮)
    func stopRecordingImmediately() {
        audioRecorder?.stop()
        isRecording = false
        print("🛑 硬件录音已停止，等待用户命名...")
        
        // 恢复播放模式，以便用户试听
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }
    
    // 2. 用户点“保存”后调用：将刚才的文件加入列表
    func confirmSave(name: String) {
        let newItem = SoundItem(name: name.isEmpty ? "新录音" : name,
                                filename: currentRecordingName,
                                isSystem: false,
                                isSelected: true)
        sounds.append(newItem)
        saveSounds()
        print("💾 录音信息已保存")
    }
    
    // 3. 用户点“丢弃”后调用：删除刚才产生的临时文件
    func discardLastRecording() {
        let url = documentsPath.appendingPathComponent(currentRecordingName)
        try? FileManager.default.removeItem(at: url)
        print("🗑️ 临时录音文件已删除")
    }
    
    func cancelRec() {
        audioRecorder?.stop()
        isRecording = false
        print("❌ 录音取消")
    }
    
    // MARK: - 音频编辑功能
        
        // 裁切音频
    func trimAudio(sourceURL: URL, startTime: Double, endTime: Double, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: sourceURL)
        
        // 导出配置
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil)
            return
        }
        
        // 创建新文件名
        let newName = "trim_\(Int(Date().timeIntervalSince1970)).m4a"
        let outputURL = documentsPath.appendingPathComponent(newName)
        
        // 删除可能存在的同名文件
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // 设置裁切时间范围
        let start = CMTime(seconds: startTime, preferredTimescale: 1000)
        let duration = CMTime(seconds: endTime - startTime, preferredTimescale: 1000)
        exportSession.timeRange = CMTimeRange(start: start, duration: duration)
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    completion(outputURL)
                } else {
                    print("裁切失败: \(String(describing: exportSession.error))")
                    completion(nil)
                }
            }
        }
    }
    
    func updateVolume(for itemID: UUID, newVolume: Float) {
            if let index = sounds.firstIndex(where: { $0.id == itemID }) {
                sounds[index].volume = newVolume
                saveSounds() // 保存到磁盘
                print("🔊 音量已更新为: \(newVolume)")
            }
        }
    
    // 替换原文件 (裁切后覆盖)
    func replaceSoundFile(for itemID: UUID, newURL: URL) {
        if let index = sounds.firstIndex(where: { $0.id == itemID }) {
            // 1. 删除旧文件 (如果是用户录音)
            let oldFilename = sounds[index].filename
            if !sounds[index].isSystem {
                let oldPath = documentsPath.appendingPathComponent(oldFilename)
                try? FileManager.default.removeItem(at: oldPath)
            }
            
            // 2. 更新数据模型指向新文件
            sounds[index].filename = newURL.lastPathComponent
            saveSounds()
        }
    }
}
