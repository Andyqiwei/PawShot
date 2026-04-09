import SwiftUI

struct SoundLibraryView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @ObservedObject var soundManager: SoundManager
    @Environment(\.dismiss) private var dismiss

    var embedInTab: Bool = false

    @State private var showNameAlert = false
    @State private var recordingName = ""
    @State private var isAnimating = false
    @State private var editingItem: SoundItem?

    private var L: L10n { appSettings.strings }
    private var palette: ThemePalette { appSettings.palette }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.cream.ignoresSafeArea()

                ScrollViewReader { proxy in
                    List {
                        Section {
                            recordHeroCard
                                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 12, trailing: 18))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .captureRect(4)
                        }
                        .id("studioTop")

                        Section {
                            librarySectionHeader {
                                withAnimation { proxy.scrollTo("studioTop", anchor: .top) }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .captureRect(5)
                        }

                        if soundManager.sounds.isEmpty {
                            Section {
                                Text(L.soundsEmpty)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .captureRect(5)
                            }
                        } else {
                            Section {
                                Group {
                                    ForEach(soundManager.sounds) { item in
                                        soundRow(item)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                    }
                                    .onDelete(perform: soundManager.deleteSound)
                                }
                                .captureRect(5)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedInTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.studioDone) { dismiss() }
                    }
                }
            }
            .alert(L.saveRecordingTitle, isPresented: $showNameAlert) {
                TextField(L.namePlaceholder, text: $recordingName)
                Button(L.save) {
                    soundManager.confirmSave(name: recordingName)
                    recordingName = ""
                }
                Button(L.discard, role: .cancel) {
                    soundManager.discardLastRecording()
                }
            }
            .sheet(item: $editingItem) { item in
                AudioEditorView(soundItem: item, soundManager: soundManager)
            }
        }
    }

    private var recordHeroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.cardGradientTop,
                            palette.cardGradientBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: palette.primary.opacity(0.35), radius: 18, y: 10)

            VStack(spacing: 18) {
                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 112, height: 112)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text(L.recordVoiceTitle)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(L.recordVoiceSubtitle)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 12)
                }

                if soundManager.isRecording {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .opacity(isAnimating ? 0.45 : 1.0)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                    isAnimating = true
                                }
                            }
                        Text(L.recording)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Button {
                            soundManager.stopRecordingImmediately()
                            isAnimating = false
                            showNameAlert = true
                        } label: {
                            Text(L.stop)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.95))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    Button {
                        soundManager.startRec()
                    } label: {
                        Text(L.record)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(palette.recordYellow)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 4)

                    if !soundManager.permissionGranted {
                        Text(L.micPermissionNeeded)
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.95))
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(.vertical, 28)
        }
        .frame(minHeight: 320)
    }

    private func librarySectionHeader(scrollToTop: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L.library)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primary)
            Spacer()
            Button(action: scrollToTop) {
                Text(L.allSounds)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.tealAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private func soundRow(_ item: SoundItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(palette.recordYellow.opacity(0.95))
                    .frame(width: 48, height: 48)
                Image(systemName: item.isSystem ? "toy.fill" : "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.primary)
            }

            Button {
                editingItem = item
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.primary)
                            .multilineTextAlignment(.leading)
                        Text(item.isSystem ? L.soundSystem : L.soundCustom)
                            .font(.caption)
                            .foregroundStyle(palette.primary.opacity(0.55))
                    }
                    Spacer(minLength: 8)
                    if !item.isSystem {
                        Image(systemName: "scissors")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primary.opacity(0.4))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.primary.opacity(0.25))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                soundManager.toggleSelection(for: item)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            item.isSelected ? palette.primary : palette.primary.opacity(0.35)
                        )
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isSelected ? L.a11ySoundInRotation : L.a11ySoundNotInRotation)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: palette.primary.opacity(0.08), radius: 10, y: 4)
        )
    }
}
