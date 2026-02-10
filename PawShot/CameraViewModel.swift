import SwiftUI
import AVFoundation
import Photos
import Combine
import UIKit
import Vision

// 1. 诱导模式
enum AttractionMode: Sendable {
    case day       // 日间：闪3下关
    case night     // 夜间：闪3下开
    case constant  // 常亮
}

struct SessionPhoto: Identifiable, Hashable {
    let id = UUID()
    let thumbnail: UIImage
    let localIdentifier: String
}

// 面部数据
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
    var isAIEnabled = false
    var isAIScanning = false
    
    // ⏳ 防抖与冷却
    private var lastCaptureTime = Date.distantPast
    private let cooldownInterval: TimeInterval = 2.0
    private var stabilityCounter = 0        // 连续合格帧计数器
    private let stabilityThreshold = 3      // 需要连续 3 帧合格才抓拍
    
    private var attractionTimer: Timer?
    
    // iOS 17 姿态请求
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
        setTorch(on: false)
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.onSessionRunningChanged?(false)
            }
        }
    }
    
    func setAIScanning(_ scanning: Bool) {
        sessionQueue.async {
            self.isAIScanning = scanning
            self.stabilityCounter = 0 // 重置计数器
            if !scanning {
                self.onFaceFeaturesDetected?(nil)
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
    
    // 强制抓拍（无视AI状态，静音）
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
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
    
    func triggerAttractionLight(mode: AttractionMode) {
        DispatchQueue.main.async { [weak self] in
            self?.runAttractionSequence(mode: mode)
        }
    }
    
    func setConstantLight(_ on: Bool) {
        sessionQueue.async {
            self.setTorch(on: on, level: 1.0)
        }
    }
    
    private func runAttractionSequence(mode: AttractionMode) {
        if mode == .constant {
            setTorchAsync(on: true)
            return
        }
        var count = 0
        attractionTimer?.invalidate()
        attractionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            let shouldBeOn = (count % 2 == 0)
            if count >= 6 {
                timer.invalidate()
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
    
    // MARK: - AI 核心逻辑 (多层过滤)
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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
            // 没狗，重置计数器
            self.stabilityCounter = 0
            self.onFaceFeaturesDetected?(nil)
            return
        }
        
        do {
            let allPoints = try observation.recognizedPoints(.all)
            
            // 1. 严格置信度过滤 (提升到 0.6)
            guard let leftEye = allPoints[.leftEye], leftEye.confidence > 0.6,
                  let rightEye = allPoints[.rightEye], rightEye.confidence > 0.6,
                  let nose = allPoints[.nose], nose.confidence > 0.6 else {
                self.stabilityCounter = 0
                self.onFaceFeaturesDetected?(nil)
                return
            }
            
            // 2. 几何校验
            let geometryPass = isValidFaceGeometry(leftEye: leftEye.location, rightEye: rightEye.location, nose: nose.location)
            
            // 3. 构建 UI 数据
            let features = DogFaceFeatures(
                isDetected: true,
                isLookingAtCamera: geometryPass, // 只有几何校验通过才算看镜头
                leftEye: leftEye.location,
                rightEye: rightEye.location,
                nose: nose.location,
                boundingBox: CGRect.zero
            )
            
            self.onFaceFeaturesDetected?(features)
            
            // 4. 防抖计数器与抓拍
            if geometryPass {
                let now = Date()
                if now.timeIntervalSince(lastCaptureTime) > cooldownInterval {
                    // 连续 3 帧合格才拍
                    stabilityCounter += 1
                    if stabilityCounter >= stabilityThreshold {
                        print("🐶 稳定锁定 (连续\(stabilityCounter)帧) -> 抓拍")
                        stabilityCounter = 0 // 拍完重置
                        lastCaptureTime = Date()
                        DispatchQueue.main.async { [weak self] in
                            NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoCapture"), object: nil)
                        }
                    }
                }
            } else {
                // 几何校验失败 (比如歪头太厉害，或者鼻子比眼睛高)
                stabilityCounter = 0
            }
            
        } catch {
            print("Keypoint error: \(error)")
        }
    }
    
    // 📐 核心几何算法：防止拍屁股
    private func isValidFaceGeometry(leftEye: CGPoint, rightEye: CGPoint, nose: CGPoint) -> Bool {
        // Vision 坐标系：左下角(0,0)，右上角(1,1)
        // 正常情况下：眼睛的 Y 值应该 > 鼻子的 Y 值 (眼睛在上方)
        
        // Check 1: 垂直位置 (最重要！防止背影误判)
        let eyesY = (leftEye.y + rightEye.y) / 2.0
        if nose.y >= eyesY {
            // 鼻子比眼睛高，绝对是误判 (或者倒立)
            return false
        }
        
        // Check 2: 对称性 (左右偏转检测)
        let eyesMidX = (leftEye.x + rightEye.x) / 2.0
        let eyeDistance = abs(leftEye.x - rightEye.x)
        let deviation = abs(nose.x - eyesMidX)
        
        // 鼻子偏离中心不得超过眼距的 30%
        if deviation > (eyeDistance * 0.3) {
            return false
        }
        
        // Check 3: 三角形比例 (上下俯仰检测)
        // 垂直距离 / 眼距。正常狗脸大概在 0.3 - 1.2 之间
        let verticalDist = abs(eyesY - nose.y)
        let ratio = verticalDist / eyeDistance
        
        if ratio < 0.2 || ratio > 1.5 {
            return false
        }
        
        return true
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
    @Published var attractionMode: AttractionMode = .day
    
    @Published var isAIEnabled: Bool = false {
        didSet {
            cameraService.isAIEnabled = isAIEnabled
            if !isAIEnabled { isAIScanning = false }
        }
    }
    @Published var isAIScanning: Bool = false {
        didSet { cameraService.setAIScanning(isAIScanning) }
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
    
    func triggerManualSound() { playAttractionSound() }
    
    func triggerManualFlash() {
        cameraService.triggerAttractionLight(mode: attractionMode)
    }
    
    func cycleAttractionMode() {
        switch attractionMode {
        case .day: attractionMode = .night
        case .night: attractionMode = .constant
        case .constant: attractionMode = .day
        }
        if attractionMode == .constant {
            cameraService.setConstantLight(true)
        } else {
            cameraService.setConstantLight(false)
        }
    }
    
    // 主快门 (AI Start/Stop 或 普通拍照)
    func handleShutterPress() {
        if isAIEnabled {
            isAIScanning.toggle()
        } else {
            cameraService.capturePhoto()
        }
    }
    
    // 强制抓拍 (右侧按钮用)
    func forceCapture() {
        // 无论 AI 状态如何，直接抓拍，不影响 AI 扫描状态
        cameraService.capturePhoto()
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
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
        cameraService.stop()
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
