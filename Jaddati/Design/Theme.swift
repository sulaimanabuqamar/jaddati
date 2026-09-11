import SwiftUI

/// The single source of truth for how Jaddati looks.
/// Warm ivory ground, deep forest green for weight, bronze for warmth.
/// Everything in the app pulls from here — no ad-hoc colours in views.
enum Theme {

    // MARK: Colour

    enum Palette {
        static let ivory       = Color(hex: 0xF7F3EA)   // page ground
        static let ivorySunk   = Color(hex: 0xEFE9DC)   // recessed fills
        static let card        = Color(hex: 0xFFFCF6)   // raised surfaces
        static let forest      = Color(hex: 0x1B4234)   // primary
        static let forestDeep  = Color(hex: 0x0E2A21)   // pressed / deep ground
        static let bronze      = Color(hex: 0xA9793F)   // accent
        static let bronzeSoft  = Color(hex: 0xD9BC93)   // accent tint
        static let ink         = Color(hex: 0x23201A)   // primary text
        static let inkSoft     = Color(hex: 0x6E6558)   // secondary text
        static let hairline    = Color(hex: 0xE0D8C8)
        static let danger      = Color(hex: 0x9B3B2E)

        // Origin colours. Sage always means a real recording of the person;
        // wine always means audio the machine made. They are never swapped and
        // never used decoratively, because a colour that means two things means
        // nothing. Colour is also never the only carrier — see SourceBadge.
        static let sage        = Color(hex: 0x4E6853)   // original recording
        static let sageSoft    = Color(hex: 0xDCE5DC)
        static let wine        = Color(hex: 0x6E2433)   // AI-recreated
        static let wineSoft    = Color(hex: 0xF0DDE0)
    }

    // MARK: Type
    // Serif for anything emotional (names, spoken words), system for controls.

    enum Font {
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .serif)
        }
        static func displayMedium(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .serif)
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
        static let control: CGFloat = 14
        static let pill: CGFloat = 999
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
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ivory)
                .frame(maxWidth: .infinity, minHeight: 52)
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
                .foregroundStyle(isEnabled ? Theme.Palette.forest
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
            if let imageURL, let data = try? Data(contentsOf: imageURL),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.Palette.forest.opacity(0.10)
                    .overlay(
                        Text(initial)
                            .font(Theme.Font.displayMedium(size * 0.38))
                            .foregroundStyle(Theme.Palette.forest)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
    }

    private var initial: String {
        let first = name.trimmingCharacters(in: .whitespaces).first
        return first.map { String($0) } ?? "؟"
    }
}

/// The label that keeps original recordings and generated audio visibly distinct.
/// This appears anywhere audio can be played. It is not decorative — it is the
/// product's honesty requirement, so it never gets hidden behind a setting.
struct SourceBadge: View {
    let isGenerated: Bool

    private var tint: Color { isGenerated ? Theme.Palette.wine : Theme.Palette.sage }
    private var fill: Color { isGenerated ? Theme.Palette.wineSoft : Theme.Palette.sageSoft }

    var body: some View {
        HStack(spacing: 5) {
            // The icon and the words both carry the meaning. Someone who cannot
            // separate sage from wine still reads the label, and a screenshot
            // that loses colour still says which one it is.
            Image(systemName: isGenerated ? "waveform.badge.exclamationmark" : "mic.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(L(isGenerated ? "AI-recreated voice" : "Original recording"))
                .font(.system(size: 11, weight: .semibold))
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
                        .foregroundStyle(selected ? Theme.Palette.ivory : Theme.Palette.forest)
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
                    Button("Try again", action: retry)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.forest)
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
