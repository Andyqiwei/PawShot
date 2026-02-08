import SwiftUI

struct SoundLibraryView: View {
    @ObservedObject var soundManager: SoundManager
    @Environment(\.dismiss) var dismiss
    
    // 状态管理
    @State private var showNameAlert = false
    @State private var recordingName = ""
    @State private var isAnimating = false
    
    // ✅ 新增：当前正在编辑的声音对象 (用于触发 Sheet)
    @State private var editingItem: SoundItem?
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - 1. 录音控制区
                Section(header: Text("录制新声音")) {
                    if soundManager.isRecording {
                        // 🔴 正在录音状态
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.red)
                                .font(.title)
                                .opacity(isAnimating ? 0.5 : 1.0) // 呼吸动画
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                        isAnimating = true
                                    }
                                }
                            
                            Text("正在录音...")
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            // 🛑 立即停止按钮
                            Button("停止") {
                                // 1. 马上切断硬件录音
                                soundManager.stopRecordingImmediately()
                                // 2. 停止动画
                                isAnimating = false
                                // 3. 弹出命名框
                                showNameAlert = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    } else {
                        // ⚪️ 准备录音状态
                        Button(action: {
                            soundManager.startRec()
                        }) {
                            HStack {
                                Image(systemName: "mic.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                VStack(alignment: .leading) {
                                    Text("点击开始录音")
                                        .foregroundColor(.primary)
                                    
                                    // 权限提示
                                    if !soundManager.permissionGranted {
                                        Text("需要麦克风权限")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // MARK: - 2. 声音列表区
                Section(header: Text("播放列表 (点击名称可剪辑)")) {
                    if soundManager.sounds.isEmpty {
                        Text("暂无声音，请录制")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(soundManager.sounds) { item in
                            HStack {
                                // ✅ 勾选按钮 (加入随机播放池)
                                Button(action: {
                                    soundManager.toggleSelection(for: item)
                                }) {
                                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.isSelected ? .green : .gray)
                                        .font(.title2)
                                }
                                .buttonStyle(.plain) // 防止点击穿透
                                
                                // ✅ 编辑入口 (点击名字进入编辑器)
                                Button(action: {
                                    editingItem = item // 赋值后自动弹出 Sheet
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(item.isSystem ? "系统内置" : "我的录音")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        // 编辑图标提示
                                        if !item.isSystem {
                                            Image(systemName: "scissors")
                                                .font(.caption)
                                                .foregroundColor(.blue.opacity(0.6))
                                        } else {
                                            // 系统声音显示锁或者是只读
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                                .foregroundColor(.gray.opacity(0.3))
                                        }
                                    }
                                    .contentShape(Rectangle()) // 扩大点击区域
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onDelete(perform: soundManager.deleteSound)
                    }
                }
            }
            .navigationTitle("声音库")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            // MARK: - 弹窗逻辑
            // 1. 命名保存弹窗
            .alert("保存录音", isPresented: $showNameAlert) {
                TextField("输入名字", text: $recordingName)
                Button("保存") {
                    soundManager.confirmSave(name: recordingName)
                    recordingName = ""
                }
                Button("丢弃", role: .cancel) {
                    soundManager.discardLastRecording()
                }
            }
            // 2. 音频编辑器弹窗
            .sheet(item: $editingItem) { item in
                // 这里调用我们刚刚写的 AudioEditorView
                AudioEditorView(soundItem: item, soundManager: soundManager)
            }
        }
    }
}
