import SwiftUI
import AVFoundation
import Photos
import Combine
import UIKit
import Vision

// 1. 定义诱导灯光模式
enum AttractionMode: Sendable {
    case day       // 日间吸引：闪烁3下 -> 关闭
    case night     // 夜间吸引：闪烁3下 -> 保持常亮
    case constant  // 常亮模式：一直亮着
}

struct SessionPhoto: Identifiable, Hashable {
    let id = UUID()
    let thumbnail: UIImage
    let localIdentifier: String
}

// 狗狗面部数据
struct DogFaceFeatures: Equatable {
    var isDetected: Bool
    var isLookingAtCamera: Bool
    var leftEye: CGPoint
    var rightEye: CGPoint
    var nose: CGPoint
    var boundingBox: CGRect
}

// 2. 硬件服务层
private class CameraService: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    
    private var currentInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.pawshot.cameraQueue")
    
    // AI 状态
    var isAIEnabled = false      // AI 模式是否选中
    var isAIScanning = false     // AI 是否正在运行 (按下快门后)
    
    private var lastCaptureTime = Date.distantPast
    private let cooldownInterval: TimeInterval = 2.0
    
    // 手动诱导闪光计时器
    private var attractionTimer: Timer?
    
    // iOS 17 动物姿态请求
    private lazy var poseRequest: VNDetectAnimalBodyPoseRequest = {
        let request = VNDetectAnimalBodyPoseRequest { [weak self] request, error in
            self?.handlePoseResults(request, error: error)
        }
        return request
    }()
    
    // 回调
    var onSessionRunningChanged: ((Bool) -> Void)?
    var onPhotoCaptured: ((UIImage) -> Void)?
    var onZoomRangeChanged: ((CGFloat, CGFloat) -> Void)?
    var onFaceFeaturesDetected: ((DogFaceFeatures?) -> Void)?
    
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
        setTorch(on: false) // 停止时关灯
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.onSessionRunningChanged?(false)
            }
        }
    }
    
    // 更新 AI 扫描状态
    func setAIScanning(_ scanning: Bool) {
        sessionQueue.async {
            self.isAIScanning = scanning
            if !scanning {
                self.onFaceFeaturesDetected?(nil) // 停止时清空 HUD
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
    
    func setZoomFactor(_ factor: CGFloat) {
         sessionQueue.async { [weak self] in
             guard let self = self, let device = self.currentInput?.device else { return }
             let clamped = min(max(factor, self.minZoomFactor), self.maxZoomFactor)
             do {
                 try device.lockForConfiguration()
                 device.videoZoomFactor = clamped
                 device.unlockForConfiguration()
             } catch { print("Zoom error: \(error)") }
         }
     }
    
    // 拍照逻辑：完全静音，不打闪光 (除非常亮模式本身就亮着)
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off // 强制关闭闪光
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
        // 拍照时短暂暂停 AI 更新，防止卡顿
        let wasScanning = isAIScanning
        sessionQueue.async { self.isAIScanning = false }
        
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            let format = [AVVideoCodecKey: AVVideoCodecType.hevc]
            let newSettings = AVCapturePhotoSettings(format: format)
            newSettings.flashMode = .off
            newSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
            photoOutput.capturePhoto(with: newSettings, delegate: self)
        } else {
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        
        sessionQueue.asyncAfter(deadline: .now() + 0.5) {
            if wasScanning { self.isAIScanning = true }
        }
    }
    
    // ✅ 新增：处理诱导灯光逻辑
    func triggerAttractionLight(mode: AttractionMode) {
        DispatchQueue.main.async { [weak self] in
            self?.runAttractionSequence(mode: mode)
        }
    }
    
    // ✅ 新增：切换常亮模式
    func setConstantLight(_ on: Bool) {
        sessionQueue.async {
            self.setTorch(on: on, level: 1.0)
        }
    }
    
    private func runAttractionSequence(mode: AttractionMode) {
        // 如果是常亮模式，手动按钮无效(或者保持常亮)
        if mode == .constant {
            setTorchAsync(on: true)
            return
        }
        
        var count = 0
        attractionTimer?.invalidate()
        
        // 0.1秒间隔，闪烁3次 (开-关-开-关-开-关 = 6次状态变化)
        attractionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            let shouldBeOn = (count % 2 == 0)
            
            // 6次动作后结束
            if count >= 6 {
                timer.invalidate()
                // 结束后状态：日间->关，夜间->开
                let finalState = (mode == .night)
                self.setTorchAsync(on: finalState)
            } else {
                self.setTorchAsync(on: shouldBeOn)
            }
            
            count += 1
        }
    }
    
    func setTorchAsync(on: Bool, level: Float = 1.0) {
        sessionQueue.async { self.setTorch(on: on, level: level) }
    }
    
    private func setTorch(on: Bool, level: Float = 1.0) {
        guard let device = currentInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: level) }
            else { device.torchMode = .off }
            device.unlockForConfiguration()
        } catch { print("Torch error: \(error)") }
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
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        }
        
        session.commitConfiguration()
    }
    
    private func updateZoomRangeFromCurrentDevice() {
        guard let device = currentInput?.device else { return }
        minZoomFactor = 1.0
        let deviceMax = CGFloat(device.activeFormat.videoMaxZoomFactor)
        maxZoomFactor = min(deviceMax, 50)
        if maxZoomFactor < 1.0 { maxZoomFactor = 1.0 }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onZoomRangeChanged?(self.minZoomFactor, self.maxZoomFactor)
        }
    }
    
    // MARK: - AI Logic (iOS 17)
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // ✅ 核心修改：只有当 AI 模式选中 且 用户按下了开始(isAIScanning) 才检测
        guard isAIEnabled && isAIScanning else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var orientation: CGImagePropertyOrientation = .right
        if let device = currentInput?.device, device.position == .front {
            orientation = .leftMirrored
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([poseRequest])
        } catch {
            print("Vision error: \(error)")
        }
    }
    
    private func handlePoseResults(_ request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNAnimalBodyPoseObservation],
              let observation = results.first else {
            self.onFaceFeaturesDetected?(nil)
            return
        }
        
        do {
            let allPoints = try observation.recognizedPoints(.all)
            
            guard let leftEye = allPoints[.leftEye], leftEye.confidence > 0.3,
                  let rightEye = allPoints[.rightEye], rightEye.confidence > 0.3,
                  let nose = allPoints[.nose], nose.confidence > 0.3 else {
                self.onFaceFeaturesDetected?(nil)
                return
            }
            
            let eyesMidX = (leftEye.location.x + rightEye.location.x) / 2.0
            let eyeDistance = abs(leftEye.location.x - rightEye.location.x)
            let deviation = abs(nose.location.x - eyesMidX)
            
            let isSymmetrical = deviation < (eyeDistance * 0.25)
            
            let features = DogFaceFeatures(
                isDetected: true,
                isLookingAtCamera: isSymmetrical,
                leftEye: leftEye.location,
                rightEye: rightEye.location,
                nose: nose.location,
                boundingBox: CGRect.zero
            )
            
            self.onFaceFeaturesDetected?(features)
            
            if isSymmetrical {
                let now = Date()
                if now.timeIntervalSince(lastCaptureTime) > cooldownInterval {
                    lastCaptureTime = Date()
                    DispatchQueue.main.async { [weak self] in
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoCapture"), object: nil)
                    }
                }
            }
            
        } catch {
            print("Keypoint extraction error: \(error)")
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { print("Error: \(error)"); return }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        onPhotoCaptured?(image)
    }
}

// 3. 主 ViewModel
@MainActor
class CameraViewModel: ObservableObject {
    
    @Published var isSessionRunning = false
    @Published var attractionMode: AttractionMode = .day // 默认为日间模式
    
    // AI 状态
    @Published var isAIEnabled: Bool = false { // AI 模式是否被选中
        didSet {
            cameraService.isAIEnabled = isAIEnabled
            // 切换模式时，重置扫描状态
            if !isAIEnabled {
                isAIScanning = false
            }
        }
    }
    @Published var isAIScanning: Bool = false { // AI 是否正在扫描(由快门控制)
        didSet {
            cameraService.setAIScanning(isAIScanning)
        }
    }
    
    @Published var detectedFace: DogFaceFeatures?
    @Published var zoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 1.0
    @Published var lastCapturedThumbnail: UIImage?
    @Published var sessionPhotos: [SessionPhoto] = []
    
    var soundManager = SoundManager()
    private let cameraService = CameraService()
    var session: AVCaptureSession { cameraService.session }
    
    private var audioPlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
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
        
        cameraService.onFaceFeaturesDetected = { [weak self] features in
            Task { @MainActor in
                self?.detectedFace = features
            }
        }
        
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerAutoCapture"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.cameraService.capturePhoto()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
            .store(in: &cancellables)
    }
    
    // ✅ 手动诱导：播放声音
    func triggerManualSound() { playAttractionSound() }
    
    // ✅ 手动诱导：根据左上角的设置触发灯光
    func triggerManualFlash() {
        cameraService.triggerAttractionLight(mode: attractionMode)
    }
    
    // ✅ 切换左上角的诱导模式
    func cycleAttractionMode() {
        switch attractionMode {
        case .day: attractionMode = .night
        case .night: attractionMode = .constant
        case .constant: attractionMode = .day
        }
        
        // 如果切到了常亮，立马开灯；否则关灯等待手动触发
        if attractionMode == .constant {
            cameraService.setConstantLight(true)
        } else {
            cameraService.setConstantLight(false)
        }
    }
    
    // ✅ 核心快门逻辑
    func handleShutterPress() {
        if isAIEnabled {
            // AI 模式下：快门 = 开始/停止扫描
            isAIScanning.toggle()
        } else {
            // 普通模式下：快门 = 立即拍照
            cameraService.capturePhoto()
        }
    }
    
    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(1.0, factor), maxZoomFactor)
        zoomFactor = clamped
        cameraService.setZoomFactor(clamped)
    }
    
    func deleteSessionPhoto(localIdentifier: String) {
        sessionPhotos.removeAll { $0.localIdentifier == localIdentifier }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }
    
    func deleteSessionPhotos(localIdentifiers: [String]) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        } completionHandler: { success, error in
            if success {
                Task { @MainActor in
                    self.sessionPhotos.removeAll { localIdentifiers.contains($0.localIdentifier) }
                }
            }
        }
    }
    
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
    func stopSession() {
        // 关闭相册时，如果是常亮模式，回来时可能需要保持；
        // 但为了简单，暂停session时会自动关灯。
        // 这里我们只需要确保 session 停止
        cameraService.stop()
        // 停止扫描
        if isAIScanning { isAIScanning = false }
    }
    
    func switchCamera() { cameraService.switchCamera() }
    
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
