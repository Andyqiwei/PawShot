import SwiftUI
import AVFoundation

struct AudioEditorView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let soundItem: SoundItem
    @ObservedObject var soundManager: SoundManager
    @Environment(\.dismiss) private var dismiss

    private var L: L10n { appSettings.strings }
    private var palette: ThemePalette { appSettings.palette }

    @State private var waveformSamples: [Float] = []
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 1

    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    @State private var isProcessing = false

    @State private var volume: Float = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                palette.cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    profileHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if duration > 0 {
                        ScrollView {
                            VStack(spacing: 18) {
                                waveformSection
                                volumeBoostSection
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        }

                        bottomActionBar
                            .padding(.horizontal, 18)
                            .padding(.bottom, 28)
                    } else {
                        Spacer()
                        ProgressView(L.analyzingWaveform)
                            .tint(palette.primary)
                        Spacer()
                    }
                }
            }
            .navigationTitle(L.editSound)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                            Text(L.backToStudio)
                                .font(.body.weight(.medium))
                        }
                        .foregroundStyle(palette.primary)
                    }
                }
            }
        }
        .onAppear(perform: loadAudioData)
        .onDisappear { stopPreview() }
    }

    private var profileHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.recordYellow)
                    .frame(width: 72, height: 72)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
            }
            Text(soundItem.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)

            if duration > 0 {
                Text("\(formatDurationClock(duration)) \(L.durationHighFidelity)")
                    .font(.subheadline)
                    .foregroundStyle(palette.primary.opacity(0.5))
            } else {
                Text(soundItem.isSystem ? L.soundSystem : L.soundCustom)
                    .font(.subheadline)
                    .foregroundStyle(palette.primary.opacity(0.5))
            }
        }
    }

    private func formatDurationClock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private var waveformSection: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.waveformPlate)
                    .frame(height: 140)

                ZStack(alignment: .leading) {
                    BarWaveformView(samples: waveformSamples, burgundy: palette.primary, altPink: palette.waveformBarAlt)
                        .frame(height: 120)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let startX = w * CGFloat(startTime / duration)
                        let endX = w * CGFloat(endTime / duration)

                        Rectangle()
                            .fill(palette.primary.opacity(0.12))
                            .frame(width: max(0, endX - startX), height: 120)
                            .offset(x: startX)
                            .padding(.vertical, 10)
                    }
                    .frame(height: 140)
                    .allowsHitTesting(false)

                    Rectangle()
                        .fill(palette.tealAccent.opacity(0.85))
                        .frame(width: 2, height: 108)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    GeometryReader { geo in
                        let width = geo.size.width
                        TrimDragHandle(handleColor: palette.purpleHandle)
                            .position(x: width * CGFloat(startTime / duration), y: 70)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newTime = (value.location.x / width) * duration
                                        startTime = min(max(0, newTime), endTime - 0.2)
                                    }
                            )

                        TrimDragHandle(handleColor: palette.purpleHandle)
                            .position(x: width * CGFloat(endTime / duration), y: 70)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newTime = (value.location.x / width) * duration
                                        endTime = max(min(duration, newTime), startTime + 0.2)
                                    }
                            )
                    }
                    .frame(height: 140)
                }
            }

            HStack {
                Text(formatTime(startTime))
                Spacer()
                Text(formatTime(endTime))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.primary.opacity(0.55))
            .padding(.horizontal, 6)
        }
    }

    private var volumeBoostSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: volume > 1.0 ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(palette.primary)
                Text(L.volumeBoost)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primary)
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(volume > 1.0 ? palette.boostOrange : palette.primary)
                    .frame(minWidth: 52, alignment: .trailing)
            }

            VolumeBoostSlider(volume: volumeBinding, palette: palette)
                .frame(height: 52)

            if volume > 1.0 {
                Text(L.volumeBoostMax)
                    .font(.caption2)
                    .foregroundStyle(palette.boostOrange)
            } else if volume == 1.0 {
                Text(L.volumeStandard)
                    .font(.caption2)
                    .foregroundStyle(palette.primary.opacity(0.45))
            } else {
                Text(L.volumeReduced)
                    .font(.caption2)
                    .foregroundStyle(palette.primary.opacity(0.45))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.waveformPlate.opacity(0.92))
        )
    }

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { volume },
            set: { applyVolumeChange($0) }
        )
    }

    private func applyVolumeChange(_ newValue: Float) {
        var v = newValue
        if abs(v - 1.0) < 0.03 {
            if volume != 1.0 {
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
            }
            v = 1.0
        }
        volume = v
        player?.volume = v
    }

    private var bottomActionBar: some View {
        HStack(spacing: 14) {
            Button(action: togglePreview) {
                HStack(spacing: 10) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text(isPlaying ? L.stop : L.preview)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .shadow(color: palette.primary.opacity(0.08), radius: 8, y: 3)
                )
            }
            .buttonStyle(.plain)

            Button(action: saveChanges) {
                HStack(spacing: 10) {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text(L.save)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.saveGradientTop, palette.saveGradientBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: palette.primary.opacity(0.35), radius: 10, y: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }

    private func loadAudioData() {
        volume = soundItem.volume

        let url: URL
        if soundItem.isSystem {
            url = Bundle.main.url(forResource: soundItem.filename, withExtension: "wav")!
        } else {
            url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(soundItem.filename)
        }

        let asset = AVAsset(url: url)
        Task {
            do {
                let durationTime = try await asset.load(.duration)
                await MainActor.run {
                    duration = durationTime.seconds
                    endTime = duration
                }
                extractWaveform(from: url)
            } catch {
                await MainActor.run { duration = 0 }
            }
        }
    }

    private func extractWaveform(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else { return }

            try? file.read(into: buffer)

            let frameCount = Int(file.length)
            let samplesPerPoint = frameCount / 100
            guard let channelData = buffer.floatChannelData?[0] else { return }

            var points: [Float] = []

            if samplesPerPoint > 0 {
                for i in 0..<100 {
                    let start = i * samplesPerPoint
                    if start + samplesPerPoint < frameCount {
                        var sum: Float = 0
                        for j in 0..<samplesPerPoint {
                            let sample = channelData[start + j]
                            sum += sample * sample
                        }
                        points.append(sqrt(sum / Float(samplesPerPoint)))
                    }
                }
            }

            if let maxV = points.max(), maxV > 0 {
                points = points.map { $0 / maxV }
            }

            DispatchQueue.main.async {
                self.waveformSamples = points
            }
        }
    }

    private func togglePreview() {
        if isPlaying {
            stopPreview()
        } else {
            playPreview()
        }
    }

    private func playPreview() {
        let url: URL
        if soundItem.isSystem {
            url = Bundle.main.url(forResource: soundItem.filename, withExtension: "wav")!
        } else {
            url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(soundItem.filename)
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.currentTime = startTime
            player?.volume = volume
            player?.play()
            isPlaying = true

            Timer.scheduledTimer(withTimeInterval: endTime - startTime, repeats: false) { _ in
                stopPreview()
            }
        } catch {
            print("播放失败")
        }
    }

    private func stopPreview() {
        player?.stop()
        isPlaying = false
    }

    private func saveChanges() {
        isProcessing = true
        stopPreview()

        soundManager.updateVolume(for: soundItem.id, newVolume: volume)

        let url: URL
        if soundItem.isSystem {
            url = Bundle.main.url(forResource: soundItem.filename, withExtension: "wav")!
        } else {
            url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(soundItem.filename)
        }

        let isTimeChanged = (abs(startTime) > 0.1 || abs(endTime - duration) > 0.1)

        if isTimeChanged {
            soundManager.trimAudio(sourceURL: url, startTime: startTime, endTime: endTime) { newURL in
                isProcessing = false
                if let newURL = newURL {
                    if !soundItem.isSystem {
                        soundManager.replaceSoundFile(for: soundItem.id, newURL: newURL)
                    } else {
                        let newItem = SoundItem(
                            name: L.trimmedSoundName(soundItem.name),
                            filename: newURL.lastPathComponent,
                            isSystem: false,
                            isSelected: true,
                            volume: volume
                        )
                        soundManager.sounds.append(newItem)
                        soundManager.saveSounds()
                    }
                    dismiss()
                }
            }
        } else {
            isProcessing = false
            dismiss()
        }
    }

    private func formatTime(_ time: Double) -> String {
        String(format: "%.1fs", time)
    }
}

// MARK: - Bar waveform

private struct BarWaveformView: View {
    let samples: [Float]
    let burgundy: Color
    let altPink: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let n = samples.count
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(n - 1, 0))
            let barW = n > 0 ? max(2, (w - totalSpacing) / CGFloat(n)) : 2

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, s in
                    RoundedRectangle(cornerRadius: barW / 2, style: .continuous)
                        .fill(index.isMultiple(of: 2) ? burgundy : altPink)
                        .frame(width: barW, height: max(4, CGFloat(s) * h * 0.92))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Trim handles

private struct TrimDragHandle: View {
    var handleColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(handleColor)
                .frame(width: 5, height: 120)

            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .heavy))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(handleColor)
            .padding(6)
            .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
        }
    }
}

// MARK: - Volume boost slider (0–100% burgundy/pink, 100–150% orange)

private struct VolumeBoostSlider: View {
    @Binding var volume: Float
    var palette: ThemePalette

    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2 - 8
            let fillEnd = w * CGFloat(volume / 1.5)
            let splitX = w * CGFloat(1.0 / 1.5)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.sliderTrack.opacity(0.55))
                    .frame(width: w, height: trackHeight)
                    .position(x: w / 2, y: cy)

                ZStack(alignment: .leading) {
                    if fillEnd > 0 {
                        HStack(spacing: 0) {
                            let burgundyW = min(fillEnd, splitX)
                            if burgundyW > 0 {
                                LinearGradient(
                                    colors: [palette.primary, palette.waveformBarAlt],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: burgundyW, height: trackHeight)
                            }
                            if fillEnd > splitX {
                                palette.boostOrange
                                    .frame(width: fillEnd - splitX, height: trackHeight)
                            }
                        }
                        .clipShape(Capsule())
                        .frame(width: fillEnd, alignment: .leading)
                    }
                }
                .frame(width: w, height: trackHeight, alignment: .leading)
                .position(x: w / 2, y: cy)
                .allowsHitTesting(false)

                let thumbCenterX = fillEnd
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(palette.boostOrange, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    .position(x: thumbCenterX, y: cy)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(0, gesture.location.x), w)
                        volume = Float(x / w) * 1.5
                    }
            )

            VStack {
                Spacer()
                HStack {
                    Text("0%")
                    Spacer()
                    Text("100%")
                    Spacer()
                    Text("150%")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.primary.opacity(0.45))
                .padding(.horizontal, 2)
                .padding(.top, 6)
            }
        }
    }
}
