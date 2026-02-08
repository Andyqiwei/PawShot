import SwiftUI
import Photos

/// 用于 sheet 的轻量包装
private struct PhotoSheetItem: Identifiable {
    let id: String
    var localIdentifier: String { id }
}

struct SessionGalleryView: View {
    @ObservedObject var cameraVM: CameraViewModel
    @Environment(\.dismiss) var dismiss
    var onDismiss: (() -> Void)?
    
    // 状态：批量选择模式
    @State private var isEditing = false // 是否处于选择模式
    @State private var selectedItems = Set<String>() // 已选中的照片 ID
    
    // 状态：单张大图查看
    @State private var selectedSheetItem: PhotoSheetItem?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. 内容区域
                if cameraVM.sessionPhotos.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(cameraVM.sessionPhotos) { item in
                                PhotoGridCell(
                                    item: item,
                                    isEditing: isEditing,
                                    isSelected: selectedItems.contains(item.localIdentifier),
                                    onTap: {
                                        if isEditing {
                                            toggleSelection(for: item.localIdentifier)
                                        } else {
                                            // 非编辑模式，点击查看大图
                                            selectedSheetItem = PhotoSheetItem(id: item.localIdentifier)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                
                // MARK: - 2. 底部工具栏 (仅在编辑模式显示)
                if isEditing {
                    VStack {
                        Divider()
                        HStack {
                            Text("已选 \(selectedItems.count) 张")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // 🗑️ 批量删除按钮
                            Button(role: .destructive) {
                                performBatchDelete()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title3)
                            }
                            .disabled(selectedItems.isEmpty)
                        }
                        .padding()
                        .background(Color(UIColor.systemBackground))
                    }
                }
            }
            .navigationTitle(isEditing ? "选择照片" : "本次拍摄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左侧：关闭
                ToolbarItem(placement: .cancellationAction) {
                    if !isEditing {
                        Button("关闭") {
                            onDismiss?()
                            dismiss()
                        }
                    }
                }
                
                // 右侧：选择/完成
                ToolbarItem(placement: .primaryAction) {
                    if !cameraVM.sessionPhotos.isEmpty {
                        Button(isEditing ? "完成" : "选择") {
                            withAnimation {
                                isEditing.toggle()
                                selectedItems.removeAll() // 退出编辑时清空选择
                            }
                        }
                    }
                }
            }
            // MARK: - 单张大图查看 Sheet
            .sheet(item: $selectedSheetItem) { item in
                FullPhotoView(
                    localIdentifier: item.localIdentifier,
                    onDismiss: { selectedSheetItem = nil },
                    onDelete: {
                        let id = item.localIdentifier
                        selectedSheetItem = nil
                        
                        // ✅ 修复点：这里直接用 cameraVM，千万不要加 $
                        // 使用 DispatchQueue 避免 UI 冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            cameraVM.deleteSessionPhoto(localIdentifier: id)
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - 辅助逻辑
    
    private var emptyStateView: some View {
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
    }
    
    private func toggleSelection(for id: String) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }
    
    private func performBatchDelete() {
        let idsToDelete = Array(selectedItems)
        // 调用 ViewModel 的批量删除
        cameraVM.deleteSessionPhotos(localIdentifiers: idsToDelete)
        
        // 删除后退出编辑模式
        withAnimation {
            isEditing = false
            selectedItems.removeAll()
        }
    }
}

// MARK: - 子视图：单个照片格子
struct PhotoGridCell: View {
    let item: SessionPhoto
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                // 1. 照片缩略图
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .opacity(isEditing && !isSelected ? 0.7 : 1.0) // 未选中时稍微变暗
                
                // 2. 选择勾选框 (仅编辑模式)
                if isEditing {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.blue : Color.black.opacity(0.4))
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 子视图：大图查看
private final class LoadCancellation {
    var isCancelled = false
}

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
