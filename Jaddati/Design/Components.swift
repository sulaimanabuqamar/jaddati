import SwiftUI

/// The design's own measurements, read out of its stylesheet rather than
/// guessed at. Keeping them named means a screen that drifts is obvious.
extension Theme {
    enum Metric {
        static let appBar: CGFloat        = 53
        static let screenPadding: CGFloat = 20
        static let heroRadius: CGFloat    = 24
        static let cardRadius: CGFloat    = 19
        static let featureRadius: CGFloat = 20
        static let buttonRadius: CGFloat  = 15
        static let buttonHeight: CGFloat  = 52
        static let touchTarget: CGFloat   = 44
    }
}

// MARK: - Chrome

/// Back chevron, centred title, globe. 53pt, on paper, no bottom rule.
struct AppBar: View {
    var title: String = ""
    /// Tab roots have nothing to go back to. Everything else does, and gets a
    /// chevron by default — this used to be opt-IN and no caller ever opted in,
    /// so every pushed screen drew a back-button-shaped hole with nothing in it
    /// and the only way out was an invisible edge swipe.
    var showsBack: Bool = true
    var onBack: (() -> Void)? = nil
    var trailing: AnyView? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = Localization.shared

    private static let glyphInset  = Theme.Metric.screenPadding - Theme.Metric.touchTarget / 2 + 6
    private static let circleInset = Theme.Metric.screenPadding
                                   - (Theme.Metric.touchTarget - GlobeButton.diameter) / 2

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if showsBack {
                    Button {
                        if let onBack { onBack() } else { dismiss() }
                    } label: {
                        // Mirrors in Arabic: a back arrow is directional.
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                            .frame(width: Theme.Metric.touchTarget,
                                   height: Theme.Metric.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("Back"))
                } else {
                    Color.clear.frame(width: Theme.Metric.touchTarget,
                                      height: Theme.Metric.touchTarget)
                }
            }

            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)

            Group {
                if let trailing {
                    trailing
                } else {
                    GlobeButton()
                }
            }
            .frame(width: Theme.Metric.touchTarget, height: Theme.Metric.touchTarget)
        }
        // Two different insets on purpose. The back chevron is a small glyph
        // centred in a 44pt tap box, so it needs a small inset to sit ON the
        // 20pt content grid; the globe is a 36pt drawn circle in the same box,
        // so it needs a larger one for its EDGE to land there. One symmetric
        // padding aligned the chevron and left the globe hanging 12pt past
        // everything else on the screen.
        .padding(.leading, Self.glyphInset)
        .padding(.trailing, Self.circleInset)
        .frame(height: Theme.Metric.appBar)
        .background(Theme.Palette.paper)
    }
}

/// One tap, both directions. The globe sits on every screen because the design
/// puts it there — a language you can only change from a settings screen is a
/// language the app does not really speak.
struct GlobeButton: View {
    /// The drawn circle, which is what the eye aligns to — not the tap box.
    static let diameter: CGFloat = 36

    @ObservedObject private var localization = Localization.shared

    var body: some View {
        Button {
            localization.toggle()
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: Self.diameter, height: Self.diameter)
                .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel(L("Language"))
        .accessibilityValue(localization.language.endonym)
    }
}

/// People · Saved · Books. Person-scoped screens carry a breadcrumb instead of
/// hiding which person they belong to.
struct TabRail: View {
    @Binding var selection: RootTab
    @EnvironmentObject private var library: Library

    /// A letter whose day has come has to be findable without remembering
    /// whose it was, so the rail carries it from wherever you are.
    private var due: Int { library.letters.filter(\.isDue).count }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                let on = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: on ? .semibold : .regular))
                            .overlay(alignment: .topTrailing) {
                                if tab == .letters && due > 0 {
                                    Circle()
                                        .fill(Theme.Palette.danger)
                                        .frame(width: 7, height: 7)
                                        .overlay(Circle().stroke(Theme.Palette.paper, lineWidth: 1.5))
                                        .offset(x: 5, y: -2)
                                }
                            }
                        Text(tab.title)
                            .font(.system(size: 10, weight: on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? Theme.Palette.wine : Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metric.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(
            Theme.Palette.paper
                .overlay(Theme.Palette.hairline.frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Saved and Books used to be tabs. Both were scoped to one person, so from a
/// cold start two thirds of the rail answered "Choose someone first" — a tab
/// bar that does nothing is the fastest way to make an app feel confusing.
/// These three all work with nothing in the app yet.
enum RootTab: String, CaseIterable, Hashable {
    case people, letters, you

    var title: String {
        switch self {
        case .people:  return L("People")
        case .letters: return L("Letters")
        case .you:     return L("You")
        }
    }

    var icon: String {
        switch self {
        case .people:  return "house"
        case .letters: return "lock"
        case .you:     return "person"
        }
    }
}

// MARK: - Type

/// The design's signature: a two-line Georgia headline at the top of a screen.
struct Headline: View {
    let text: String
    var size: CGFloat = 37

    var body: some View {
        Text(text)
            .font(Theme.Font.display(size))
            .tracking(-1.3)
            .lineSpacing(size * 0.13 - 2)
            .foregroundStyle(Theme.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 11)
            .padding(.bottom, 14)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            // Letter spacing breaks the joins in Arabic — Theme says so, and
            // these two components were the place still doing it.
            .tracking(uiIsArabic ? 0 : 1)
            .foregroundStyle(Theme.Palette.inkSoft)
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(uiIsArabic ? 0 : 1.7)
            .foregroundStyle(Theme.Palette.inkSoft)
    }
}

/// Secondary body copy. 13pt, generous leading, muted.
struct SubText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(4 + Theme.textLineSpacing)
            .foregroundStyle(Theme.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The person a screen belongs to, named rather than assumed.
struct Breadcrumb: View {
    let name: String
    let relationship: String
    let photo: URL?

    var body: some View {
        HStack(spacing: 8) {
            PersonAvatar(name: name, imageURL: photo, size: 22)
            BidiText(value: relationship.isEmpty ? name : "\(name) · \(relationship)",
                     font: .system(size: 13),
                     colour: Theme.Palette.inkSoft,
                     lineLimit: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Surfaces

/// The wine statement card. One per screen at most.
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(23)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.heroRadius, style: .continuous)
                    .fill(Theme.Palette.wine)
            )
    }
}

/// The one emphasised row on the person screen. Wine, like the hero.
struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var emphasised: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(emphasised ? Color(hex: 0xF9EFE6) : Theme.Palette.wine)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(emphasised
                                  ? Color.white.opacity(0.10)
                                  : Theme.Palette.sunk)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Font.display(emphasised ? 24 : 17))
                    .foregroundStyle(emphasised ? Color(hex: 0xF9EFE6) : Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(emphasised
                                     ? Color(hex: 0xF9EFE6).opacity(0.82)
                                     : Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(emphasised
                                 ? Color(hex: 0xF9EFE6).opacity(0.7)
                                 : Color(hex: 0x958578))
        }
        .padding(emphasised ? 20 : 0)
        .padding(.vertical, emphasised ? 0 : 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.featureRadius, style: .continuous)
                .fill(emphasised ? Theme.Palette.wine : Color.clear)
        )
    }
}

/// A hairline, at the design's own rhythm.
struct QuietDivider: View {
    var body: some View {
        Theme.Palette.hairline
            .frame(height: 1)
            .padding(.vertical, 20)
    }
}

/// A book, drawn as a book. Spine on the leading edge, title set in the serif.
struct BookCover: View {
    let title: String
    var tint: Color = Theme.Palette.coverGreen

    var body: some View {
        VStack(spacing: 6) {
            Text(L("JADDATI"))
                .font(.system(size: 7, weight: .semibold))
                .tracking(1.2)
            Text(title)
                .font(Theme.Font.display(14))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(L("FAMILY SHELF"))
                .font(.system(size: 6, weight: .semibold))
                .tracking(1.1)
        }
        .foregroundStyle(Color(hex: 0xF4EBDB))
        .padding(.vertical, 11)
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .frame(width: 80, height: 113)
        .background(
            tint.overlay(Color.black.opacity(0.13).frame(width: 5), alignment: .leading)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: Color(hex: 0x493B28).opacity(0.13), radius: 3, x: 3, y: 4)
        .accessibilityHidden(true)
    }
}

/// The still mark on the listening screen. An arch with concentric rings — an
/// archive stamp, not a level meter. Nothing here moves with the audio, because
/// we do not have the sample data and drawing one anyway would be a lie.
struct PlayerArt: View {
    var body: some View {
        ZStack {
            ForEach(1..<5) { ring in
                ArchShape(baseCorner: 25)
                    .stroke(Theme.Palette.wine.opacity(0.22), lineWidth: 1)
                    .padding(CGFloat(ring) * 11)
            }
            Circle()
                .fill(Theme.Palette.wine.opacity(0.55))
                .frame(width: 7, height: 7)
        }
        .frame(width: 116, height: 139)
        .background(
            ArchShape(baseCorner: 25).fill(Color(hex: 0xE9DDCE))
        )
        .overlay(
            ArchShape(baseCorner: 25).stroke(Color(hex: 0xD8C5B1), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

/// An example figure, marked as one. The design shows prices so the interface
/// can be reviewed; it labels every one of them illustrative, and so does this.
struct ExampleQuote: View {
    let characters: Int

    /// Roughly one credit per character at the provider. Shown as an example
    /// only — it is not a quote, and nothing here takes a payment.
    private var usd: Double { Double(characters) * 0.00011 }

    var body: some View {
        HStack {
            Text(L("This clip · example quote"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer()
            Text(String(format: "$%.2f", max(usd, 0.01)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text(L("USD"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.vertical, 12)
        .overlay(Theme.Palette.hairline.frame(height: 1), alignment: .top)
    }
}
