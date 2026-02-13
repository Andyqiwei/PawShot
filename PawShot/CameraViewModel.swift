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
    
    // 🔒 连拍锁与缓存
    private var isCapturingBurst = false
    private var burstBuffer: [UIImage] = []
    private var expectedBurstCount = 0
    private let burstTotalCount = 4
    
    // ⏳ 算法状态
    private var lastCaptureTime = Date.distantPast
    private let cooldownInterval: TimeInterval = 1.5
    private var stabilityCounter = 0
    private let stabilityThreshold = 2
    
    private var previousNosePoint: CGPoint?
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
        
        // 🚀 核心加速：后台静默预热 AI 模型
        prewarmVisionModel()
        
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }
    
    // 喂一张空图片，强制 Vision 提前载入神经网络模型
    private func prewarmVisionModel() {
        DispatchQueue.global(qos: .userInitiated).async {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo),
                  let cgImage = context.makeImage() else { return }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNDetectAnimalBodyPoseRequest()
            do {
                try handler.perform([request])
                print("🚀 [Pre-warm] AI 神经网络模型预热完成！")
            } catch {
                print("AI Pre-warm failed: \(error)")
            }
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
            self.stabilityCounter = 0
            self.previousNosePoint = nil
            self.isCapturingBurst = false
            self.burstBuffer.removeAll()
            
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
    
    // MARK: - 📸 智能拍摄路由
    
    func forceCapture() {
        sessionQueue.async {
            self.captureSinglePhoto(isBurst: false)
        }
    }
    
    func smartCapture(preferBurst: Bool) {
        sessionQueue.async {
            if preferBurst {
                self.performBurstCapture()
            } else {
                print("📸 狗狗稳定，单张极速抓拍")
                self.captureSinglePhoto(isBurst: false)
            }
        }
    }
    
    private func performBurstCapture() {
        if self.isCapturingBurst { return }
        self.isCapturingBurst = true
        self.burstBuffer.removeAll()
        self.expectedBurstCount = self.burstTotalCount
        
        print("🚀 狗狗微动，启动极速连拍优选: 目标 \(self.burstTotalCount) 张")
        for _ in 0..<self.burstTotalCount {
            self.captureSinglePhoto(isBurst: true)
        }
    }
    
    private func captureSinglePhoto(isBurst: Bool) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
        // 连拍用 .speed，单张用 .balanced (ZSL)
        if isBurst {
            settings.photoQualityPrioritization = .speed
        } else {
            settings.photoQualityPrioritization = .balanced
        }
        
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            let format = [AVVideoCodecKey: AVVideoCodecType.hevc]
            let newSettings = AVCapturePhotoSettings(format: format)
            newSettings.flashMode = .off
            newSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
            newSettings.photoQualityPrioritization = settings.photoQualityPrioritization
            photoOutput.capturePhoto(with: newSettings, delegate: self)
        } else {
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    // MARK: - 图片处理 (Delegate)
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { print("Error: \(error)"); return }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.isCapturingBurst {
                self.burstBuffer.append(image)
                self.expectedBurstCount -= 1
                
                if self.expectedBurstCount <= 0 {
                    print("🔍 AI 优选最佳照片...")
                    if let bestImage = self.selectBestImage(from: self.burstBuffer) {
                        self.onPhotoCaptured?(bestImage)
                    } else {
                        self.onPhotoCaptured?(image)
                    }
                    
                    self.burstBuffer.removeAll()
                    self.sessionQueue.asyncAfter(deadline: .now() + 1.0) {
                        self.isCapturingBurst = false
                        self.stabilityCounter = 0
                        self.previousNosePoint = nil
                        print("🔓 连拍完成，AI 解锁")
                    }
                }
            } else {
                self.onPhotoCaptured?(image)
                self.stabilityCounter = 0
            }
        }
    }
    
    private func selectBestImage(from images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images.first }
        
        var bestImage: UIImage? = images.last
        var maxScore: Float = -1.0
        
        for image in images {
            let score = calculateImageScore(image)
            if score > maxScore {
                maxScore = score
                bestImage = image
            }
        }
        return bestImage
    }
    
    private func calculateImageScore(_ image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0 }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let request = VNDetectAnimalBodyPoseRequest()
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return 0 }
            let points = try observation.recognizedPoints(.all)
            guard let leftEye = points[.leftEye], let nose = points[.nose] else { return 0.1 }
            return leftEye.confidence + nose.confidence
        } catch { return 0 }
    }
    
    // MARK: - 诱导与配置
    
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
            
            do {
                try input.device.lockForConfiguration()
                if input.device.isFocusModeSupported(.continuousAutoFocus) {
                    input.device.focusMode = .continuousAutoFocus
                }
                if input.device.isSmoothAutoFocusSupported {
                    input.device.isSmoothAutoFocusEnabled = true
                }
                input.device.unlockForConfiguration()
            } catch { print("Focus Error: \(error)") }
            
            updateZoomRangeFromCurrentDevice()
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .balanced
            
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
    
    // MARK: - AI 核心逻辑
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAIEnabled && isAIScanning && !isCapturingBurst else { return }
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
        if isCapturingBurst { return }
        
        guard let results = request.results as? [VNAnimalBodyPoseObservation],
              let observation = results.first else {
            resetStability()
            self.onFaceFeaturesDetected?(nil)
            return
        }
        
        do {
            let allPoints = try observation.recognizedPoints(.all)
            
            guard let leftEye = allPoints[.leftEye], leftEye.confidence > 0.6,
                  let rightEye = allPoints[.rightEye], rightEye.confidence > 0.6,
                  let nose = allPoints[.nose], nose.confidence > 0.6 else {
                resetStability()
                self.onFaceFeaturesDetected?(nil)
                return
            }
            
            let geometryPass = isValidFaceGeometry(leftEye: leftEye.location, rightEye: rightEye.location, nose: nose.location)
            let motionAnalysis = analyzeMotionAndLight(currentNose: nose.location)
            self.previousNosePoint = nose.location
            
            let features = DogFaceFeatures(
                isDetected: true,
                isLookingAtCamera: geometryPass,
                leftEye: leftEye.location,
                rightEye: rightEye.location,
                nose: nose.location,
                boundingBox: CGRect.zero
            )
            self.onFaceFeaturesDetected?(features)
            
            if geometryPass && motionAnalysis.passed {
                let now = Date()
                if now.timeIntervalSince(lastCaptureTime) > cooldownInterval {
                    stabilityCounter += 1
                    if stabilityCounter >= stabilityThreshold {
                        let preferBurst = motionAnalysis.needsBurst
                        stabilityCounter = 0
                        lastCaptureTime = Date()
                        
                        DispatchQueue.main.async { [weak self] in
                            NotificationCenter.default.post(
                                name: NSNotification.Name("TriggerAutoCapture"),
                                object: nil,
                                userInfo: ["preferBurst": preferBurst]
                            )
                        }
                    }
                }
            } else {
                stabilityCounter = max(0, stabilityCounter - 1)
            }
            
        } catch {
            print("Keypoint error: \(error)")
        }
    }
    
    private func resetStability() {
        self.stabilityCounter = 0
        self.previousNosePoint = nil
    }
    
    private func analyzeMotionAndLight(currentNose: CGPoint) -> (passed: Bool, needsBurst: Bool) {
        guard let prev = previousNosePoint else { return (false, false) }
        
        let dx = currentNose.x - prev.x
        let dy = currentNose.y - prev.y
        let distance = sqrt(dx*dx + dy*dy)
        let currentISO = currentInput?.device.iso ?? 100
        
        let maxVelocityThreshold: CGFloat
        if currentISO < 200 { maxVelocityThreshold = 0.04 }
        else if currentISO < 800 { maxVelocityThreshold = 0.02 }
        else { maxVelocityThreshold = 0.005 }
        
        if distance > maxVelocityThreshold {
            return (false, false)
        }
        
        let stableThreshold: CGFloat = 0.003
        let needsBurst = distance > stableThreshold
        
        return (true, needsBurst)
    }
    
    private func isValidFaceGeometry(leftEye: CGPoint, rightEye: CGPoint, nose: CGPoint) -> Bool {
        let eyesY = (leftEye.y + rightEye.y) / 2.0
        if nose.y >= eyesY { return false }
        
        let eyesMidX = (leftEye.x + rightEye.x) / 2.0
        let eyeDistance = abs(leftEye.x - rightEye.x)
        let deviation = abs(nose.x - eyesMidX)
        if deviation > (eyeDistance * 0.35) { return false }
        
        let verticalDist = abs(eyesY - nose.y)
        let ratio = verticalDist / eyeDistance
        if ratio < 0.2 || ratio > 1.6 { return false }
        
        return true
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
            .sink { [weak self] notification in
                Task { @MainActor in
                    let preferBurst = notification.userInfo?["preferBurst"] as? Bool ?? false
                    self?.cameraService.smartCapture(preferBurst: preferBurst)
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
    
    func handleShutterPress() {
        if isAIEnabled {
            isAIScanning.toggle()
        } else {
            cameraService.forceCapture()
        }
    }
    
    func forceCapture() {
        cameraService.forceCapture()
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
