import SwiftUI
import UIKit

/// The single source of truth for how Jaddati looks.
/// Warm ivory ground, deep forest green for weight, bronze for warmth.
/// Everything in the app pulls from here — no ad-hoc colours in views.
enum Theme {

    // MARK: Colour

    /// The design's own tokens, read out of its `:root` block rather than
    /// eyeballed. Wine is the primary: cards, buttons, and the selected state
    /// of anything. Sage always means a real recording of the person; wine
    /// always means audio the machine made.
    enum Palette {
        static let paper       = Color.dynamic(light: 0xF9F5EF, dark: 0x14100E)
        static let ink         = Color.dynamic(light: 0x302725, dark: 0xF2EAE1)
        static let inkSoft     = Color.dynamic(light: 0x766861, dark: 0xA89B92)
        static let hairline    = Color.dynamic(light: 0xE4DCD3, dark: 0x332A25)

        /// Wine as a FILL — buttons, the hero card.
        static let wine        = Color.dynamic(light: 0x592C43, dark: 0x7A3D5B)
        static let wineDeep    = Color.dynamic(light: 0x3E2031, dark: 0x5E2E46)
        /// Wine as TEXT or an icon. On near-white paper these are the same
        /// colour; on a dark ground they cannot be. A wine dark enough to
        /// carry cream text is 2.4:1 against the dark ground behind it, so
        /// the foreground is lifted until it measures 5.99:1.
        static let wineInk     = Color.dynamic(light: 0x592C43, dark: 0xC67A99)
        static let wineLight   = Color.dynamic(light: 0xF0E5EB, dark: 0x2E1C26)

        static let sage        = Color.dynamic(light: 0x426858, dark: 0x6E9C87)
        static let sageLight   = Color.dynamic(light: 0xE8EEE5, dark: 0x1C2620)

        static let amber       = Color.dynamic(light: 0x775829, dark: 0xC4954E)
        static let amberLight  = Color.dynamic(light: 0xF5EAD5, dark: 0x2A2113)
        static let danger      = Color.dynamic(light: 0x963E3B, dark: 0xD9736F)

        /// Raised surfaces and recessed fills, derived from paper rather than
        /// invented — the design uses paper with a line, not a second white.
        static let card        = Color.dynamic(light: 0xFEFAF5, dark: 0x1E1815)
        static let bar         = Color.dynamic(light: 0xF9F6EF, dark: 0x14100E)
        static let sunk        = Color.dynamic(light: 0xF1EBE3, dark: 0x241D19)

        static let archWarm    = Color.dynamic(light: 0xE9E0D5, dark: 0x3A302A)
        static let archSage    = Color.dynamic(light: 0xE1E6DD, dark: 0x2A322C)
        static let coverGreen  = Color.dynamic(light: 0x6C7052, dark: 0x6C7052)
        static let coverRust   = Color.dynamic(light: 0xA0765E, dark: 0xA0765E)

        /// Written inline all over the app until dark mode arrived, where a
        /// hardcoded colour cannot follow the appearance. The person cards
        /// were filled with card2 by hand — so in dark they stayed cream
        /// while the names on them went near-white and vanished.
        static let card2       = Color.dynamic(light: 0xFFFAF4, dark: 0x231C18)
        static let chevron     = Color.dynamic(light: 0x958578, dark: 0x6B5E55)
        static let artFill     = Color.dynamic(light: 0xE9DDCE, dark: 0x2A221D)
        static let artEdge     = Color.dynamic(light: 0xD8C5B1, dark: 0x3D332C)

        /// Cream is the text ON wine, and wine is wine in both appearances,
        /// so these two do not change — but they are tokens now so nobody has
        /// to work out which inline hex was deliberate.
        static let cream       = Color.dynamic(light: 0xF9EFE6, dark: 0xF9EFE6)
        static let cream2      = Color.dynamic(light: 0xF8EFE4, dark: 0xF8EFE4)
        static let coverInk    = Color.dynamic(light: 0xF4EBDB, dark: 0xF4EBDB)
        /// The drop under a book on the shelf. Ink-brown on paper; on a
        /// dark shelf a brown shadow is invisible, so it goes to black.
        static let bookShadow  = Color.dynamic(light: 0x493B28, dark: 0x000000)

        // Older names the rest of the app still refers to.
        static let ivory       = paper
        static let ivorySunk   = sunk
        static let forest      = wine
        static let forestDeep  = wineDeep
        static let bronze      = amber
        static let bronzeSoft  = amberLight
        static let inkStrong   = ink
        static let inkFaint    = inkSoft
        static let wineTint    = wineLight
        static let sageTint    = sageLight
    }

    // MARK: Type
    // Serif for anything emotional (names, spoken words), system for controls.

    enum Font {
        /// Georgia, as the design specifies. It ships with iOS, so this is the
        /// same face rather than a lookalike. Arabic falls through to the
        /// system's own Arabic face, which is correct — Georgia has no Arabic.
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Georgia", size: size, relativeTo: .largeTitle)
        }
        static func displayMedium(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Georgia-Bold", size: size, relativeTo: .title)
        }
        static let title      = display(32)
        static let heading    = displayMedium(22)
        static let spoken     = display(26)     // the words being said aloud
        static let body       = SwiftUI.Font.system(size: 17)
        static let label      = SwiftUI.Font.system(size: 15, weight: .medium)
        static let caption    = SwiftUI.Font.system(size: 13)
    }

    // MARK: Metrics

    /// Arabic sets its vowel marks above the line, so a Latin line height
    /// crowds them. Never apply letter spacing to Arabic — it breaks the joins.
    static var textLineSpacing: CGFloat { uiIsArabic ? 5 : 2 }

    enum Space {
        static let xs: CGFloat = 6
        static let s:  CGFloat = 12
        static let m:  CGFloat = 20
        static let l:  CGFloat = 32
        static let xl: CGFloat = 48
    }

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 15
        static let pill: CGFloat = 999
    }
}

extension Color {
    /// One colour with two values, resolved by the phone's appearance every
    /// time it is drawn rather than fixed at launch. A plain Color(hex:) is a
    /// single value and cannot follow the system.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

extension Color {
    /// 0xRRGGBB literal -> Color. Keeps the palette readable above.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - Reusable surfaces

/// Standard raised surface. Used for every card in the app so spacing stays even.
struct Panel<Content: View>: View {
    var padding: CGFloat = Theme.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

/// The app's one primary action style. Every screen has exactly one.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, enabled: enabled)
    }

    /// Deliberately NOT named `Body`: `ButtonStyle` has an associated type by
    /// that name, and a nested type matching it must be at least as accessible
    /// as the style itself.
    ///
    /// Honours BOTH the explicit flag and `.disabled(...)`, so a caller that
    /// only used one of them still gets the greyed-out look.
    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        let enabled: Bool
        @Environment(\.isEnabled) private var isEnabled

        private var live: Bool { enabled && isEnabled }

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.cream)
                .frame(maxWidth: .infinity, minHeight: Theme.Metric.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(live ? (configuration.isPressed ? Theme.Palette.forestDeep
                                                              : Theme.Palette.forest)
                                   : Theme.Palette.inkSoft.opacity(0.35))
                )
                .scaleEffect(configuration.isPressed && live ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietBody(configuration: configuration)
    }

    /// A ButtonStyle cannot read `isEnabled` directly, so the body lives in a
    /// small view that can. Without this a disabled control looks identical to
    /// a live one — Previous and Next on the last page read as broken taps.
    ///
    /// Named `QuietBody`, not `Body`, to avoid colliding with the protocol's
    /// own `Body` associated type.
    private struct QuietBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Font.label)
                .foregroundStyle(isEnabled ? Theme.Palette.wineInk
                                           : Theme.Palette.inkSoft.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Palette.ivorySunk.opacity(isEnabled ? 1 : 0.5))
                )
                .opacity(configuration.isPressed && isEnabled ? 0.75 : 1)
        }
    }
}

/// A person's picture, or their initial when there isn't one.
struct PersonAvatar: View {
    let name: String
    let imageURL: URL?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = AvatarCache.image(for: imageURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fill
                    .overlay(
                        Text(initial)
                            .font(Theme.Font.displayMedium(size * 0.36))
                            .foregroundStyle(Theme.Palette.inkStrong.opacity(0.75))
                    )
            }
        }
        .frame(width: size, height: size * 1.14)
        .clipShape(ArchShape(baseCorner: size * 0.16))
        .accessibilityHidden(true)
    }

    /// Two quiet fills, chosen from the name so one person keeps the same one
    /// rather than shuffling every time the list redraws.
    ///
    /// NOT `hashValue`: Swift seeds string hashing per process, so the colour
    /// changed on every launch — the opposite of what this is for. `abs` on it
    /// was also a trap waiting to happen, since `abs(Int.min)` crashes.
    private var fill: Color {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sum % 2 == 0 ? Theme.Palette.archWarm : Theme.Palette.archSage
    }

    private var initial: String {
        let first = name.trimmingCharacters(in: .whitespaces).first
        return first.map { String($0) } ?? "؟"
    }
}


/// Decoded portraits, kept once each.
///
/// This exists because the obvious version — decode inside `body` — got the app
/// killed by the OS. A SwiftUI `body` runs on every state change, the audio
/// player publishes its position twenty times a second, and a 600px JPEG
/// decodes to about 1.4MB of bitmap. Decoding per render meant tens of
/// megabytes a second of live allocation while anything was playing.
///
/// Stored photos are written under a fresh UUID filename every time one is set
/// (`Library.setPhoto`), so a path is never reused and an entry can never go
/// stale. NSCache evicts itself under memory pressure.
enum AvatarCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The label that keeps original recordings and generated audio visibly distinct.
/// This appears anywhere audio can be played. It is not decorative — it is the
/// product's honesty requirement, so it never gets hidden behind a setting.
struct SourceBadge: View {
    let isGenerated: Bool

    private var tint: Color { isGenerated ? Theme.Palette.wine : Theme.Palette.sage }
    private var fill: Color { isGenerated ? Theme.Palette.wineLight : Theme.Palette.sageLight }

    var body: some View {
        HStack(spacing: 5) {
            // The icon and the words both carry the meaning. Someone who cannot
            // separate sage from wine still reads the label, and a screenshot
            // that loses colour still says which one it is.
            Image(systemName: isGenerated ? "sparkles" : "mic")
                .font(.system(size: 10, weight: .semibold))
            Text(L(isGenerated ? "AI-recreated voice" : "Original recording").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L(isGenerated ? "AI-recreated voice" : "Original recording"))
    }
}

/// What the words are, as opposed to who is speaking them. A story stays marked
/// as invented on its saved row and on every later playback, because a label
/// that disappears once the clip is filed is not a label.
struct ContentBadge: View {
    let provenance: ContentProvenance

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: provenance.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(provenance.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(Theme.Palette.inkSoft)
        .background(Capsule().fill(Theme.Palette.ivorySunk))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provenance.label)
    }
}

/// The archive arch — rounded top, squared-off base. It is the app's one motif,
/// used for avatars and for the still mark on the listening screen. Never an
/// animated blob, never a waveform pretending to be a voice.
struct ArchShape: Shape {
    var baseCorner: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / 2, rect.height / 2)
        let c = min(baseCorner, r)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - c, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - c),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Text whose direction follows its own content rather than the paragraph
/// around it — the equivalent of wrapping a run in `<bdi dir="auto">`. A Latin
/// filename inside an Arabic screen, or an Arabic name inside an English one,
/// otherwise gets dragged the wrong way and reads back to front.
struct BidiText: View {
    let value: String
    var font: Font = Theme.Font.body
    var colour: Color = Theme.Palette.ink
    var lineLimit: Int? = nil

    var body: some View {
        let rtl = TextDirection.isArabic(value)
        Text(value)
            .font(font)
            .foregroundStyle(colour)
            .lineLimit(lineLimit)
            .multilineTextAlignment(rtl ? .trailing : .leading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
}

/// Each language named in its own script. Not a flag — a flag names a country,
/// and Arabic is not one country.
struct LanguageSwitch: View {
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                let selected = localization.language == language
                Button {
                    localization.language = language
                } label: {
                    Text(language.endonym)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Theme.Palette.ivory : Theme.Palette.wineInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(
                            Capsule().fill(selected ? Theme.Palette.forest : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.endonym)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.Palette.ivorySunk))
        // 44pt minimum target, including the tap area around the capsules.
        .frame(minHeight: 44)
    }
}

/// Empty-state block. Used rather than a blank screen anywhere a list can be empty.
struct EmptyHint: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Palette.bronze)
            Text(title)
                .font(Theme.Font.heading)
                .foregroundStyle(Theme.Palette.ink)
            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.l)
    }
}

/// Inline error. Never a modal alert for recoverable failures — the user keeps
/// their typed text and can retry in place.
struct ErrorNote: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.danger)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(L("Try again"), action: retry)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.wineInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.danger.opacity(0.08))
        )
    }
}
