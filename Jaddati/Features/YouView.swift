import SwiftUI

/// Everything that is about the app rather than about a person.
///
/// There was no screen like this. Language was an unlabelled globe in a corner
/// and the privacy notice was a row at the bottom of the home screen, below
/// however many people you happened to keep — so on a full home screen it was
/// below the fold and effectively gone.
struct YouView: View {
    @EnvironmentObject private var consent: Consent
    @ObservedObject private var localization = Localization.shared

    @AppStorage(Appearance.key) private var appearance: String = Appearance.light
    @State private var showingPrivacy = false

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("You"), showsBack: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !AppConfig.isConfigured {
                        unavailableNote.padding(.top, 16)
                    }

                    SectionLabel(text: L("This app"))
                        .padding(.top, 20)

                    row(icon: "globe",
                        title: L("Language"),
                        note: localization.language.endonym) {
                        localization.toggle()
                    }

                    Theme.Palette.hairline.frame(height: 1)

                    // A switch, not a row that opens something: there are two
                    // states and the control should BE the answer.
                    Toggle(isOn: Binding(
                        get: { appearance == Appearance.dark },
                        set: { appearance = $0 ? Appearance.dark : Appearance.light })
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Dark mode"))
                                .font(Theme.Font.label)
                                .foregroundStyle(Theme.Palette.ink)
                            Text(L("The app opens light. This keeps it dark."))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.inkSoft)
                        }
                    }
                    .tint(Theme.Palette.wine)
                    .padding(.vertical, 10)
                    .frame(minHeight: Theme.Metric.touchTarget)

                    Theme.Palette.hairline.frame(height: 1)

                    row(icon: consent.allowsNetwork ? "lock.open" : "lock",
                        title: L("Privacy and data"),
                        note: consent.allowsNetwork
                            ? L("Two services outside this phone are in use.")
                            : L("Everything is being kept on this phone.")) {
                        showingPrivacy = true
                    }

                    QuietDivider()

                    identity
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showingPrivacy) { PrivacyScreen(consent: consent) }
    }

    private func row(icon: String, title: String, note: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FeatureRow(icon: icon, title: title, subtitle: note)
        }
        .buttonStyle(.plain)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Jaddati")
                    .font(Theme.Font.displayMedium(26))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 0)
                Text("جدّتي")
                    .font(Theme.Font.displayMedium(22))
                    .foregroundStyle(Theme.Palette.wineInk)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            SubText(text: L("A place for a familiar voice."))
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "seal")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text(L("Original and recreated. Always distinct."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.top, 8)
        }
    }

    private var unavailableNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConfig.unavailableTitle)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            SubText(text: AppConfig.unavailableMessage)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                .fill(Theme.Palette.card)
                .overlay(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius)
                    .stroke(Theme.Palette.hairline, lineWidth: 1))
        )
    }
}
