import SwiftUI
import Photos

/// 用于 sheet(item:) 的轻量包装，避免用含 UIImage 的 SessionPhoto 做 binding
private struct PhotoSheetItem: Identifiable {
    let id: String
    var localIdentifier: String { id }
}

/// 本次拍摄列表：网格展示、点击查看大图、菜单删除
struct SessionGalleryView: View {
    @ObservedObject var cameraVM: CameraViewModel
    @Environment(\.dismiss) var dismiss
    /// 显式关闭回调，确保点「完成」能回到主页面
    var onDismiss: (() -> Void)?
    
    @State private var selectedSheetItem: PhotoSheetItem?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    
    var body: some View {
        NavigationStack {
            Group {
                if cameraVM.sessionPhotos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)
                        Text("暂无拍摄照片")
                            .font(.headline)
                        Text("拍几张宠物照后会显示在这里")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(cameraVM.sessionPhotos) { item in
                                cell(for: item)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("本次拍摄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onDismiss?()
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedSheetItem) { item in
                FullPhotoView(
                    localIdentifier: item.localIdentifier,
                    onDismiss: { selectedSheetItem = nil },
                    onDelete: {
                        let id = item.localIdentifier
                        selectedSheetItem = nil
                        DispatchQueue.main.async {
                            cameraVM.deleteSessionPhoto(localIdentifier: id)
                        }
                    }
                )
            }
        }
    }
    
    private func cell(for item: SessionPhoto) -> some View {
        Button {
            selectedSheetItem = PhotoSheetItem(id: item.localIdentifier)
        } label: {
            Image(uiImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, minHeight: 0)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                cameraVM.deleteSessionPhoto(localIdentifier: item.localIdentifier)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// 用于在闭包里共享「已取消」状态，避免 sheet 关闭后仍更新 UI 导致崩溃
private final class LoadCancellation {
    var isCancelled = false
}

// MARK: - 大图查看（从相册拉取原图）
private struct FullPhotoView: View {
    let localIdentifier: String
    let onDismiss: () -> Void
    let onDelete: () -> Void
    
    @State private var image: UIImage?
    @State private var loading = true
    @State private var loadCancellation = LoadCancellation()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if loading {
                    ProgressView("加载中…")
                        .tint(.white)
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onDismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .onAppear(perform: loadFullImage)
            .onDisappear { loadCancellation.isCancelled = true }
        }
    }
    
    private func loadFullImage() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            loading = false
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let size = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        let token = loadCancellation
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }
                image = img
                loading = false
            }
        }
    }
}

