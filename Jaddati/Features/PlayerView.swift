import SwiftUI

/// The listening screen. This is the moment the whole product exists for, so
/// it holds nothing but the words, the voice, and the truth about its source.
///
/// The progress track is driven by `AVAudioPlayer.currentTime`. There is no
/// waveform drawn here: we do not have the sample data for generated audio, and
/// a decorative shape presented as a waveform would be a lie about the sound.
struct PlayerView: View {
    let asset: AudioAsset
    var intent: Intent? = nil

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var kept = true
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var isCurrent: Bool { player.playingAssetId == asset.id }
    private var shownProgress: Double { scrubbing ? scrubValue : (isCurrent ? player.progress : 0) }

    var body: some View {
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: Theme.Space.m)

                SourceBadge(isGenerated: asset.isGenerated)

                if !asset.text.isEmpty {
                    Text(asset.text)
                        .font(Theme.Font.spoken)
                        .foregroundStyle(Theme.Palette.ink)
                        .multilineTextAlignment(TextDirection.isArabic(asset.text) ? .trailing : .center)
                        .environment(\.layoutDirection,
                                      TextDirection.isArabic(asset.text) ? .rightToLeft : .leftToRight)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.s)
                }

                if let note = intent?.provenanceNote {
                    Text(note)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.bronze)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                transport

                if let problem = player.playbackError {
                    ErrorNote(message: problem)
                }

                if asset.isGenerated {
                    keepControls
                }

                Spacer(minLength: Theme.Space.m)
            }
            .padding(Theme.Space.m)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if library.fileExists(for: asset) {
                player.play(url: library.url(for: asset), assetId: asset.id)
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: Theme.Space.s) {
            track

            HStack {
                Text(timeString(isCurrent ? player.currentTime : 0))
                Spacer()
                Text(timeString(isCurrent && player.duration > 0
                                ? player.duration : asset.durationSeconds))
            }
            .font(Theme.Font.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.inkSoft)

            Button {
                guard library.fileExists(for: asset) else { return }
                player.play(url: library.url(for: asset), assetId: asset.id)
            } label: {
                Image(systemName: player.isPlaying(assetId: asset.id) ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.Palette.ivory)
                    .frame(width: 76, height: 76)
                    .background(
                        Circle()
                            .fill(Theme.Palette.forest)
                            .shadow(color: Theme.Palette.forest.opacity(0.25),
                                    radius: player.isPlaying(assetId: asset.id) ? 18 : 6,
                                    y: 4)
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.35), value: player.isPlaying(assetId: asset.id))
            .accessibilityLabel(player.isPlaying(assetId: asset.id) ? "Pause" : "Play")
            .padding(.top, Theme.Space.xs)
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.ivorySunk)
                    .frame(height: 6)
                Capsule()
                    .fill(Theme.Palette.bronze)
                    .frame(width: max(0, min(width, width * shownProgress)), height: 6)
                Circle()
                    .fill(Theme.Palette.forest)
                    .frame(width: 16, height: 16)
                    .offset(x: max(0, min(width - 16, width * shownProgress - 8)))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubbing = true
                        scrubValue = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        player.seek(toProgress: scrubValue)
                        scrubbing = false
                    }
            )
        }
        .frame(height: 20)
    }

    // MARK: Keep or discard

    private var keepControls: some View {
        HStack(spacing: Theme.Space.s) {
            Button(kept ? "Saved to memories" : "Save to memories") {
                guard !kept else { return }
                var updated = asset
                updated.isSaved = true
                library.update(updated)
                kept = true
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(kept)

            Button(role: .destructive) {
                player.stop()
                library.delete(asset)
                dismiss()
            } label: {
                Text("Discard")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Theme.Palette.danger.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
