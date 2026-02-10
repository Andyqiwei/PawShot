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
                    // 将 selectedPhotoId 转换为 SessionPhoto 对象以触发 sheet
                    guard let id = selectedPhotoId else { return nil }
                    return cameraVM.sessionPhotos.first(where: { $0.localIdentifier == id })
                },
                set: { obj in
                    selectedPhotoId = obj?.localIdentifier
                }
            )) { (startItem: SessionPhoto) in
                // 传入初始 ID 和 数据源
                FullImagePageView(
                    initialId: startItem.localIdentifier,
                    photos: cameraVM.sessionPhotos,
                    onDismiss: { selectedPhotoId = nil },
                    onDelete: { idToDelete in
                        cameraVM.deleteSessionPhoto(localIdentifier: idToDelete)
                        // 如果删光了，关闭预览
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
            .tabViewStyle(.page(indexDisplayMode: .never)) // 隐藏自带的点
            
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
                    // 页码指示
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

// MARK: - 支持缩放的单张图片视图
struct ZoomablePhotoView: View {
    let localIdentifier: String
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // ✅ 新增状态：控制手势是否包含拖拽
    // 只有当图片被放大时，我们才允许 DragGesture 存在，否则单指滑动交给 TabView
    @State private var isZoomed = false
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let img = image {
                    // 使用 if-else 根据缩放状态动态切换 View 结构
                    // 这样可以彻底移除 DragGesture，让 TabView 接收单指滑动
                    if isZoomed {
                        // 🔍 放大状态：支持 捏合缩放 + 拖拽移动 + 双击复原
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        let newScale = scale * delta
                                        scale = min(max(newScale, 1.0), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        withAnimation {
                                            if scale < 1.0 { scale = 1.0; offset = .zero }
                                            isZoomed = scale > 1.0
                                        }
                                    }
                                    .simultaneously(with: DragGesture()
                                        .onChanged { value in
                                            // 只有放大时才允许改变位置
                                            if scale > 1.0 {
                                                var newOffset = lastOffset
                                                newOffset.width += value.translation.width
                                                newOffset.height += value.translation.height
                                                offset = newOffset
                                            }
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                    )
                            )
                            .onTapGesture(count: 2) {
                                // 双击缩小
                                withAnimation {
                                    scale = 1.0
                                    offset = .zero
                                    isZoomed = false
                                }
                            }
                    } else {
                        // 📱 普通状态：仅支持 捏合缩放 + 双击放大
                        // 没有 DragGesture，所以单指滑动会穿透给外层的 TabView (实现左右翻页)
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        let newScale = scale * delta
                                        scale = min(max(newScale, 1.0), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        withAnimation {
                                            if scale < 1.0 { scale = 1.0; offset = .zero }
                                            // 如果放大了，切换状态以启用拖拽
                                            isZoomed = scale > 1.0
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                // 双击放大
                                withAnimation {
                                    scale = 2.0
                                    isZoomed = true
                                }
                            }
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .onAppear(perform: loadFullImage)
        // 每次切换图片时重置状态
        .onChange(of: localIdentifier) { _ in
            scale = 1.0
            offset = .zero
            lastOffset = .zero
            isZoomed = false
        }
    }
    
    private func loadFullImage() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: UIScreen.main.bounds.size,
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            DispatchQueue.main.async {
                self.image = img
            }
        }
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
