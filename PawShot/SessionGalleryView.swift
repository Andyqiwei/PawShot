import SwiftUI
import Photos

struct SessionGalleryView: View {
    @ObservedObject var cameraVM: CameraViewModel
    @Environment(\.dismiss) var dismiss
    var onDismiss: (() -> Void)?
    
    // 状态
    @State private var isEditing = false
    @State private var selectedItems = Set<String>()
    
    // 选中的大图 ID
    @State private var selectedPhotoId: String?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 内容区域
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
                                            // 点击进入大图浏览
                                            selectedPhotoId = item.localIdentifier
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                
                // 底部删除工具栏 (仅编辑模式)
                if isEditing {
                    VStack {
                        Divider()
                        HStack {
                            Text("已选 \(selectedItems.count) 张")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
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
                ToolbarItem(placement: .cancellationAction) {
                    if !isEditing {
                        Button("关闭") {
                            onDismiss?()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !cameraVM.sessionPhotos.isEmpty {
                        Button(isEditing ? "完成" : "选择") {
                            withAnimation {
                                isEditing.toggle()
                                selectedItems.removeAll()
                            }
                        }
                    }
                }
            }
            // 全屏大图浏览 Sheet
            .fullScreenCover(item: Binding<SessionPhoto?>(
                get: {
                    guard let id = selectedPhotoId else { return nil }
                    return cameraVM.sessionPhotos.first(where: { $0.localIdentifier == id })
                },
                set: { obj in
                    selectedPhotoId = obj?.localIdentifier
                }
            )) { (startItem: SessionPhoto) in
                FullImagePageView(
                    initialId: startItem.localIdentifier,
                    photos: cameraVM.sessionPhotos,
                    onDismiss: { selectedPhotoId = nil },
                    onDelete: { idToDelete in
                        cameraVM.deleteSessionPhoto(localIdentifier: idToDelete)
                        if cameraVM.sessionPhotos.isEmpty {
                            selectedPhotoId = nil
                        }
                    }
                )
            }
        }
    }
    
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
        cameraVM.deleteSessionPhotos(localIdentifiers: idsToDelete)
        withAnimation {
            isEditing = false
            selectedItems.removeAll()
        }
    }
}

// MARK: - 大图分页浏览容器
struct FullImagePageView: View {
    let initialId: String
    var photos: [SessionPhoto]
    var onDismiss: () -> Void
    var onDelete: (String) -> Void
    
    @State private var currentId: String
    
    init(initialId: String, photos: [SessionPhoto], onDismiss: @escaping () -> Void, onDelete: @escaping (String) -> Void) {
        self.initialId = initialId
        self.photos = photos
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        self._currentId = State(initialValue: initialId)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // TabView 实现左右滑动
            TabView(selection: $currentId) {
                ForEach(photos, id: \.localIdentifier) { photo in
                    ZoomablePhotoView(localIdentifier: photo.localIdentifier)
                        .tag(photo.localIdentifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // 顶部导航栏
            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                    Spacer()
                    if let index = photos.firstIndex(where: { $0.localIdentifier == currentId }) {
                        Text("\(index + 1) / \(photos.count)")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    Spacer()
                    Button(action: {
                        onDelete(currentId)
                    }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.title)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - 支持缩放的单张图片视图 (已修复模糊和手势)
struct ZoomablePhotoView: View {
    let localIdentifier: String
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // 控制是否处于放大状态
    @State private var isZoomed = false
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let img = image {
                    // 1. 基础图片视图配置
                    // 关键修复：添加 frame 和 contentShape 确保点击黑边也能触发手势
                    let imageView = Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle()) // ✅ 关键：让整个区域都可交互
                        .scaleEffect(scale)
                        .offset(offset)
                    
                    // 2. 根据缩放状态动态绑定手势
                    // 这样设计是为了在未缩放时让出单指滑动的控制权给 TabView
                    if isZoomed {
                        imageView
                            .gesture(
                                MagnificationGesture()
                                    .onChanged(onPinchChanged)
                                    .onEnded(onPinchEnded)
                                    .simultaneously(with:
                                        DragGesture()
                                            .onChanged(onDragChanged)
                                            .onEnded(onDragEnded)
                                    )
                            )
                            .onTapGesture(count: 2, perform: onDoubleTap)
                    } else {
                        imageView
                            .gesture(
                                MagnificationGesture()
                                    .onChanged(onPinchChanged)
                                    .onEnded(onPinchEnded)
                            )
                            .onTapGesture(count: 2, perform: onDoubleTap)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .onAppear(perform: loadFullImage)
        .onChange(of: localIdentifier) { _ in resetState() }
    }
    
    // MARK: - 高清加载逻辑
    private func loadFullImage() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // 确保请求高质量
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        // ✅ 关键修复：乘以屏幕缩放比例 (scale)，获取物理像素尺寸
        // 比如 iPhone 14 Pro 的 scale 是 3.0，这样才能拿到 3 倍高清图
        let screenScale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * screenScale,
            height: UIScreen.main.bounds.height * screenScale
        )
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            DispatchQueue.main.async {
                self.image = img
            }
        }
    }
    
    // MARK: - 手势处理
    
    private func onPinchChanged(value: CGFloat) {
        let delta = value / lastScale
        lastScale = value
        let newScale = scale * delta
        scale = min(max(newScale, 1.0), 5.0) // 限制最大 5 倍
    }
    
    private func onPinchEnded(value: CGFloat) {
        lastScale = 1.0
        withAnimation {
            if scale < 1.0 {
                scale = 1.0
                offset = .zero
            }
            isZoomed = scale > 1.0
        }
    }
    
    private func onDragChanged(value: DragGesture.Value) {
        // 只有在放大状态下才允许拖拽
        guard isZoomed else { return }
        let newOffset = CGSize(
            width: lastOffset.width + value.translation.width,
            height: lastOffset.height + value.translation.height
        )
        offset = newOffset
    }
    
    private func onDragEnded(value: DragGesture.Value) {
        if isZoomed {
            lastOffset = offset
        }
    }
    
    private func onDoubleTap() {
        withAnimation {
            if scale > 1.0 {
                // 缩小复原
                scale = 1.0
                offset = .zero
                lastOffset = .zero
                isZoomed = false
            } else {
                // 放大
                scale = 2.0
                isZoomed = true
            }
        }
    }
    
    private func resetState() {
        scale = 1.0
        offset = .zero
        lastOffset = .zero
        isZoomed = false
        lastScale = 1.0
    }
}

// MARK: - Grid Cell
struct PhotoGridCell: View {
    let item: SessionPhoto
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .opacity(isEditing && !isSelected ? 0.7 : 1.0)
                
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
                            Circle().stroke(Color.white, lineWidth: 2).frame(width: 22, height: 22)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
