import SwiftUI

struct SoundLibraryView: View {
    @ObservedObject var soundManager: SoundManager
    @Environment(\.dismiss) var dismiss
    
    // 状态管理
    @State private var showNameAlert = false
    @State private var recordingName = ""
    @State private var isAnimating = false // 用于 iOS 16 兼容动画
    
    // 当前正在编辑的声音对象
    @State private var editingItem: SoundItem?
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - 1. 录音控制区
                Section(header: Text("录制新声音")) {
                    if soundManager.isRecording {
                        // 🔴 正在录音状态
                        HStack {
                            // ✅ 修复：使用 opacity 动画替代 symbolEffect (兼容 iOS 16)
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.red)
                                .font(.title)
                                .opacity(isAnimating ? 0.5 : 1.0)
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
                                soundManager.stopRecordingImmediately()
                                isAnimating = false
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
                                Button(action: {
                                    soundManager.toggleSelection(for: item)
                                }) {
                                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.isSelected ? .green : .gray)
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    editingItem = item
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
                                        if !item.isSystem {
                                            Image(systemName: "scissors")
                                                .font(.caption)
                                                .foregroundColor(.blue.opacity(0.6))
                                        } else {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                                .foregroundColor(.gray.opacity(0.3))
                                        }
                                    }
                                    .contentShape(Rectangle())
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
            .sheet(item: $editingItem) { item in
                AudioEditorView(soundItem: item, soundManager: soundManager)
            }
        }
    }
}
