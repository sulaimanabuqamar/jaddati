import SwiftUI

/// The listening screen. This is the moment the whole product exists for, so
/// it holds nothing but the words, the voice, and the truth about its source.
///
/// The progress track is driven by `AVAudioPlayer.currentTime`. There is no
/// waveform drawn here: we do not have the sample data for generated audio, and
/// a decorative shape presented as a waveform would be a lie about the sound.
struct PlayerView: View {
    let asset: AudioAsset

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var kept: Bool
    @State private var confirmingDiscard = false

    init(asset: AudioAsset) {
        self.asset = asset
        _kept = State(initialValue: asset.isSaved)
    }

    private var isCurrent: Bool { player.playingAssetId == asset.id }
    private var fileIsPresent: Bool { library.fileExists(for: asset) }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Playing"))

            // A ScrollView, which this did not have.
            //
            // The content was a VStack between two Spacers, so it centred
            // nicely when it fitted and OVERFLOWED UPWARD when it did not —
            // taking the app bar off the top of the screen with it. On a clip
            // with a long transcript, or at a larger text size, the only way
            // out of this screen was to keep or discard the clip, which is
            // not a choice anyone should be forced into to leave a page.
            //
            // minHeight keeps the centred composition when there is room, and
            // lets it scroll when there is not.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.Space.l) {
                        Spacer(minLength: 0)

                        // Provenance first, words second. Which of the two things this
                        // is — a recording of them, or audio a machine made — has to be
                        // settled before anyone reads a single word of it.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { provenanceBadges }
                            VStack(spacing: 6) { provenanceBadges }
                        }

                        // A still archive mark. Nothing here moves with the sound.
                        PlayerArt()

                        if !asset.text.isEmpty {
                            Text(asset.text)
                                .font(Theme.Font.display(27))
                                .tracking(-0.35)
                                .foregroundStyle(Theme.Palette.ink)
                                .multilineTextAlignment(.center)
                                .environment(\.layoutDirection,
                                              TextDirection.isArabic(asset.text) ? .rightToLeft : .leftToRight)
                                .lineSpacing(6 + Theme.textLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.Space.s)
                        }

                        // Read from the asset, not from whichever screen opened it, so a
                        // fiction label still shows when the clip is replayed months later.
                        if let note = asset.provenance, !note.isEmpty {
                            Text(note)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.wineInk)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        // Grouped so the transport counts as one child: this stack
                        // was sitting on SwiftUI's ten-child ViewBuilder limit, where
                        // one more line fails with an unreadable inference error.
                        Group {
                            if fileIsPresent {
                                transport
                            } else {
                                ErrorNote(message: L("This audio file is not available. Playback is unavailable."))
                            }

                            if let problem = player.playbackError {
                                ErrorNote(message: problem)
                            }

                            if asset.isGenerated {
                                keepControls
                            }
                        }

                        Spacer(minLength: Theme.Space.m)
                    }
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .onAppear {
            // The player is shared, so a complaint about the LAST clip was
            // still on screen under this one.
            if player.playingAssetId != asset.id { player.playbackError = nil }
            guard fileIsPresent else { return }
            player.ensurePlaying(url: library.url(for: asset), assetId: asset.id)
        }
        .onDisappear {
            player.stop()
            // Deliberately does NOT delete an unkept clip.
            //
            // Switching language rebuilds the whole tree, and tapping a tab
            // tears down the navigation stack — both fire onDisappear. Deleting
            // here meant that changing to Arabic while the player was open
            // destroyed the clip that had just been generated and paid for.
            // Unkept clips are swept at launch instead (see Library.init).
        }
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: Theme.Space.s) {
            // The position lives on its own object, so this subview is the
            // only thing that redraws while audio is playing.
            PlaybackTrack(position: player.position,
                          isCurrent: isCurrent,
                          fallbackDuration: asset.durationSeconds,
                          onSeek: { player.seek(toProgress: $0) })

            HStack(spacing: Theme.Space.m) {
                skipButton(-skipInterval)

                Button {
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
                .accessibilityLabel(player.isPlaying(assetId: asset.id) ? L("Pause") : L("Play"))

                skipButton(skipInterval)
            }
            .padding(.top, Theme.Space.xs)

            speedControl
        }
    }

    /// Slows a clip that has ALREADY been generated and paid for. Distinct from
    /// the Pace control on the compose screen, which changes how the provider
    /// reads the NEXT thing: this one costs nothing and applies to anything,
    /// including audio made before that setting existed.
    ///
    /// It is a rate applied to the real audio file, not a re-generation, so the
    /// timeline and the elapsed clock stay truthful while it is in effect.
    private var speedControl: some View {
        HStack(spacing: 4) {
            ForEach(Self.speeds, id: \.self) { rate in
                let selected = abs(player.playbackRate - rate) < 0.01
                Button {
                    player.playbackRate = rate
                } label: {
                    Text(rate == 1.0 ? L("Normal") : String(format: "%.2g\u{00D7}", rate))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Theme.Palette.ivory : Theme.Palette.wineInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(
                            Capsule().fill(selected ? Theme.Palette.forest : Theme.Palette.ivorySunk)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Playback speed"))
                .accessibilityValue(String(format: "%.2g", rate))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .frame(minHeight: 44)
        .padding(.top, Theme.Space.xs)
    }

    private static let speeds: [Float] = [0.75, 1.0, 1.25]

    /// Sized to the clip, not fixed. A fifteen-second jump through a
    /// two-second page of a book is the whole clip and then some, so short
    /// audio gets a short step — and anything too short to jump around in at
    /// all gets no buttons, rather than two controls that do nothing useful.
    private var clipLength: Double {
        let live = player.position.duration
        return isCurrent && live > 0 ? live : asset.durationSeconds
    }

    private var skipInterval: Double {
        switch clipLength {
        case ..<60:  return 5
        case ..<180: return 10
        default:     return 15
        }
    }

    private var showsSkip: Bool { clipLength >= 12 }

    @ViewBuilder private func skipButton(_ seconds: Double) -> some View {
        if showsSkip {
            let back = seconds < 0
            Button { player.skip(by: seconds) } label: {
                Image(systemName: (back ? "gobackward." : "goforward.")
                                + String(Int(abs(seconds))))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.Palette.wineInk)
                    .frame(width: Theme.Metric.touchTarget,
                           height: Theme.Metric.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isCurrent)
            .opacity(isCurrent ? 1 : 0.35)
            .accessibilityLabel(back ? L("Back") : L("Next"))
            .accessibilityValue(Counts.number(Int(abs(seconds))))
        }
    }

    // MARK: Keep or discard

    @ViewBuilder private var keepControls: some View {
        // Leaving without keeping does exactly what Discard does — and Discard
        // asks first. Say so, rather than letting Back be the quiet one.
        if !kept {
            Text(L("Not kept yet. This clip is removed when you leave."))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.amber)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: Theme.Space.s) {
            Button(kept ? L("Clip saved") : L("Keep this clip")) {
                guard !kept else { return }
                var updated = asset
                updated.isSaved = true
                library.update(updated)
                kept = true
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(kept)

            Button(role: .destructive) {
                confirmingDiscard = true
            } label: {
                Text(L("Discard"))
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Theme.Palette.danger.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .confirmationDialog(L("Discard this clip?"),
                                isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button(L("Discard"), role: .destructive) {
                    player.stop()
                    library.delete(asset)
                    dismiss()
                }
                Button(L("Cancel"), role: .cancel) { }
            } message: {
                Text(L("The audio is deleted from this phone. Creating it again costs credits."))
            }
        }
    }

    /// Both labels, always. Colour alone never carries which is which.
    @ViewBuilder private var provenanceBadges: some View {
        SourceBadge(isGenerated: asset.isGenerated)
        if asset.isGenerated, let content = asset.contentProvenance {
            ContentBadge(provenance: content)
        }
    }
}

/// The scrubber and the clock — the only part of the app that has to redraw
/// while audio is playing, and so the only part that observes the position.
private struct PlaybackTrack: View {
    @ObservedObject var position: PlaybackPosition
    let isCurrent: Bool
    let fallbackDuration: Double
    let onSeek: (Double) -> Void

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var shown: Double {
        scrubbing ? scrubValue : (isCurrent ? position.progress : 0)
    }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)   // never divide by zero below
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.ivorySunk)
                        .frame(height: 6)
                    Capsule()
                        .fill(Theme.Palette.bronze)
                        .frame(width: max(0, min(width, width * shown)), height: 6)
                    Circle()
                        .fill(Theme.Palette.forest)
                        .frame(width: 16, height: 16)
                        .offset(x: max(0, min(width - 16, width * shown - 8)))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbing = true
                            let fraction = value.location.x / width
                            scrubValue = fraction.isFinite ? min(max(fraction, 0), 1) : 0
                        }
                        .onEnded { _ in
                            onSeek(scrubValue)
                            scrubbing = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(Self.clock(isCurrent ? position.currentTime : 0))
                Spacer()
                Text(Self.clock(isCurrent && position.duration > 0
                                ? position.duration : fallbackDuration))
            }
            .font(Theme.Font.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    private static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
