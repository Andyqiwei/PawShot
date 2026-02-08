import SwiftUI
import AVFoundation
import Photos
import Combine
import UIKit

// 1. 模式定义 (线程安全)
enum LightingMode: Sendable {
    case off
    case constant
    case strobeLightOn
    case strobeLightOff
}

/// 本次会话中拍摄的一张照片（缩略图 + 系统相册中的标识，用于应用内列表与删除）
struct SessionPhoto: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    let localIdentifier: String
}

// 2. 独立的硬件管理器 (不绑定 MainActor，专门干后台的活)
private class CameraService: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.pawshot.cameraQueue")
    
    // 弱引用回调，用于通知 ViewModel 更新 UI
    var onSessionRunningChanged: ((Bool) -> Void)?
    var onPhotoCaptured: ((UIImage) -> Void)?
    /// 变焦范围变化时回调 (min, max)，主线程
    var onZoomRangeChanged: ((CGFloat, CGFloat) -> Void)?
    
    /// 当前设备支持的变焦范围
    private(set) var minZoomFactor: CGFloat = 1.0
    private(set) var maxZoomFactor: CGFloat = 1.0
    
    override init() {
        super.init()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }
    
    func start() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                self.onSessionRunningChanged?(true)
            }
        }
    }
    
    func stop() {
        setTorch(on: false) // 关灯
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.onSessionRunningChanged?(false)
            }
        }
    }
    
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, let currentInput = self.currentInput else { return }
            
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            
            let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                self.session.addInput(currentInput)
                self.session.commitConfiguration()
                return
            }
            
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.updateZoomRangeFromCurrentDevice()
            } else {
                self.session.addInput(currentInput)
            }
            self.session.commitConfiguration()
        }
    }
    
    /// 从当前 device 读取变焦范围并通知主线程
    private func updateZoomRangeFromCurrentDevice() {
        guard let device = currentInput?.device else { return }
        minZoomFactor = 1.0
        let deviceMax = CGFloat(device.activeFormat.videoMaxZoomFactor)
        maxZoomFactor = min(deviceMax, 50)  // 上限 50 倍
        if maxZoomFactor < 1.0 { maxZoomFactor = 1.0 }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onZoomRangeChanged?(self.minZoomFactor, self.maxZoomFactor)
        }
    }
    
    /// 设置变焦倍数（在 sessionQueue 上执行，会 clamp 到 [minZoomFactor, maxZoomFactor]）
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentInput?.device else { return }
            let clamped = min(max(factor, self.minZoomFactor), self.maxZoomFactor)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                print("Zoom error: \(error)")
            }
        }
    }
    
    func capturePhoto(lightingMode: LightingMode, soundManager: SoundManager, isSoundEnabled: Bool) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            let format = [AVVideoCodecKey: AVVideoCodecType.hevc]
            let newSettings = AVCapturePhotoSettings(format: format)
            newSettings.flashMode = .off
            newSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
            photoOutput.capturePhoto(with: newSettings, delegate: self)
        } else {
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // 硬件灯光控制 (公共方法，线程安全)
    func setTorchAsync(on: Bool, level: Float = 1.0) {
        sessionQueue.async {
            self.setTorch(on: on, level: level)
        }
    }
    
    // 内部同步方法
    private func setTorch(on: Bool, level: Float = 1.0) {
        guard let device = currentInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: level) }
            else { device.torchMode = .off }
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }
    
    func getTorchState() -> Bool {
        return currentInput?.device.torchMode == .on
    }
    
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: backCamera) else { return }
        
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            updateZoomRangeFromCurrentDevice()
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            if let maxDimension = backCamera.activeFormat.supportedMaxPhotoDimensions.last {
                photoOutput.maxPhotoDimensions = maxDimension
            }
        }
        session.commitConfiguration()
    }
    
    // 回调
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { print("Error: \(error)"); return }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        onPhotoCaptured?(image)
    }
}

// 3. 主 ViewModel (只负责 UI 和逻辑协调，不直接碰硬件)
@MainActor
class CameraViewModel: ObservableObject {
    
    @Published var isSessionRunning = false
    @Published var lightingMode: LightingMode = .off
    @Published var isSoundEnabled: Bool = true
    
    /// 当前变焦倍数
    @Published var zoomFactor: CGFloat = 1.0
    /// 最大变焦倍数
    @Published var maxZoomFactor: CGFloat = 1.0
    
    /// 最近一张拍摄的照片缩略图
    @Published var lastCapturedThumbnail: UIImage?
    /// 本次会话拍摄的所有照片
    @Published var sessionPhotos: [SessionPhoto] = []
    
    var soundManager = SoundManager()
    
    // 持有后台服务
    private let cameraService = CameraService()
    var session: AVCaptureSession { cameraService.session }
    
    private var audioPlayer: AVAudioPlayer?
    private var strobeTimer: Timer?
    
    init() {
        // 绑定后台状态回调
        cameraService.onSessionRunningChanged = { [weak self] isRunning in
            Task { @MainActor in self?.isSessionRunning = isRunning }
        }
        
        cameraService.onPhotoCaptured = { [weak self] image in
            let thumb = Self.thumbnail(from: image, maxSize: 120)
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    Task { @MainActor in self?.lastCapturedThumbnail = thumb }
                    return
                }
                var savedLocalId: String?
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    savedLocalId = request.placeholderForCreatedAsset?.localIdentifier
                } completionHandler: { success, _ in
                    Task { @MainActor in
                        self?.lastCapturedThumbnail = thumb
                        if success, let localId = savedLocalId, let thumb = thumb {
                            self?.sessionPhotos.append(SessionPhoto(thumbnail: thumb, localIdentifier: localId))
                        }
                    }
                }
            }
        }
        
        cameraService.onZoomRangeChanged = { [weak self] minZoom, maxZoom in
            Task { @MainActor in
                self?.maxZoomFactor = maxZoom
                self?.zoomFactor = 1.0
                self?.cameraService.setZoomFactor(1.0)
            }
        }
    }
    
    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(1.0, factor), maxZoomFactor)
        zoomFactor = clamped
        cameraService.setZoomFactor(clamped)
    }
    
    // MARK: - 删除功能
    
    /// 删除单张
    func deleteSessionPhoto(localIdentifier: String) {
        sessionPhotos.removeAll { $0.localIdentifier == localIdentifier }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }
    
    /// ✅ 新增：批量删除多张照片
    func deleteSessionPhotos(localIdentifiers: [String]) {
        // 1. 获取 PHAssets
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return }
        
        // 2. 请求删除 (这会触发系统唯一的那个弹窗)
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        } completionHandler: { success, error in
            if success {
                // 3. 删除成功后，在主线程更新 UI 数据源
                Task { @MainActor in
                    self.sessionPhotos.removeAll { localIdentifiers.contains($0.localIdentifier) }
                }
            } else {
                print("批量删除失败: \(String(describing: error))")
            }
        }
    }
    
    /// 生成缩略图
    private static func thumbnail(from image: UIImage, maxSize: CGFloat) -> UIImage? {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return image }
        let ratio = min(maxSize / w, maxSize / h)
        if ratio >= 1 { return image }
        let newSize = CGSize(width: w * ratio, height: h * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    func startSession() { cameraService.start() }
    func stopSession() { cameraService.stop() }
    func switchCamera() { cameraService.switchCamera() }
    
    func cycleLightingMode() {
        switch lightingMode {
        case .off: lightingMode = .constant; cameraService.setTorchAsync(on: true)
        case .constant: lightingMode = .strobeLightOn; cameraService.setTorchAsync(on: false)
        case .strobeLightOn: lightingMode = .strobeLightOff; cameraService.setTorchAsync(on: false)
        case .strobeLightOff: lightingMode = .off; cameraService.setTorchAsync(on: false)
        }
    }
    
    func takePhoto() {
        switch lightingMode {
        case .off:
            if isSoundEnabled { playAttractionSound() }
            cameraService.capturePhoto(lightingMode: lightingMode, soundManager: soundManager, isSoundEnabled: isSoundEnabled)
        case .constant:
            if isSoundEnabled { playAttractionSound() }
            cameraService.capturePhoto(lightingMode: lightingMode, soundManager: soundManager, isSoundEnabled: isSoundEnabled)
        case .strobeLightOn, .strobeLightOff:
            performStrobeSequence()
        }
    }
    
    private func performStrobeSequence() {
        if isSoundEnabled { playAttractionSound() }
        
        var flashCount = 0
        strobeTimer?.invalidate()
        
        strobeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            let shouldBeOn = (flashCount % 2 == 0)
            self.cameraService.setTorchAsync(on: shouldBeOn)
            
            flashCount += 1
            
            if flashCount >= 8 {
                timer.invalidate()
                
                let currentMode = self.lightingMode
                let shouldKeepLightOn = (currentMode == .strobeLightOn)
                
                self.cameraService.setTorchAsync(on: shouldKeepLightOn)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.cameraService.capturePhoto(lightingMode: currentMode, soundManager: self.soundManager, isSoundEnabled: self.isSoundEnabled)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.lightingMode == .strobeLightOn {
                            self.cameraService.setTorchAsync(on: false)
                        }
                    }
                }
            }
        }
    }
    
    private func playAttractionSound() {
        guard let (url, volume) = soundManager.getRandomPlayableSound() else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = volume
            audioPlayer?.enableRate = true
            audioPlayer?.rate = Float.random(in: 0.9...1.3)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch { print("Audio error: \(error)") }
    }
}
