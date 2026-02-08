import SwiftUI
import AVFoundation
import UIKit

// 1. 定义一个原生的 UIKit 视图类
// 这是 Apple 官方推荐写法：将 View 的底层 Layer 直接指定为相机预览层
class UIPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// 2. 将上面的 UIKit 视图包装给 SwiftUI 使用
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIPreviewView {
        let view = UIPreviewView()
        view.backgroundColor = .black
        
        // 配置预览层
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill // 保持比例填满屏幕
        view.videoPreviewLayer.connection?.videoOrientation = .portrait // 强制竖屏
        
        return view
    }
    
    func updateUIView(_ uiView: UIPreviewView, context: Context) {
        // 这里的代码用于当 SwiftUI 状态改变时更新 View
        // 但因为我们在 makeUIView 里已经绑定了 session，这里通常不需要做什么
    }
}
