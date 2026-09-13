import SwiftUI

/// Everything that is about the app rather than about a person.
///
/// There was no screen like this. Language was an unlabelled globe in a corner
/// and the privacy notice was a row at the bottom of the home screen, below
/// however many people you happened to keep — so on a full home screen it was
/// below the fold and effectively gone.
struct YouView: View {
    @EnvironmentObject private var consent: Consent
    @EnvironmentObject private var library: Library
    @ObservedObject private var localization = Localization.shared

    /// Created here rather than injected: nothing else in the app needs it, and
    /// a StateObject keeps one instance across rebuilds of this screen so a
    /// sign-in that is in flight is not thrown away by a repaint.
    @StateObject private var cloud = CloudBackup()

    @AppStorage(Appearance.key) private var appearance: String = Appearance.light
    @State private var showingPrivacy = false
    @State private var cloudNote: String?
    @State private var cloudProblem: String?

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

                    // A screen of its own, not a row that flips the language
                    // the instant it is touched.
                    NavigationLink {
                        LanguageView()
                    } label: {
                        FeatureRow(icon: "globe",
                                   title: L("Language"),
                                   subtitle: localization.language.endonym)
                    }
                    .buttonStyle(.plain)

                    Theme.Palette.hairline.frame(height: 1)

                    row(icon: consent.allowsNetwork ? "lock.open" : "lock",
                        title: L("Privacy and data"),
                        note: consent.allowsNetwork
                            ? L("Two services outside this phone are in use.")
                            : L("Everything is being kept on this phone.")) {
                        showingPrivacy = true
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

                    QuietDivider()

                    backupSection

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

    /// Google Drive backup.
    ///
    /// Hidden entirely when no Google client is configured, the same rule the
    /// web half follows: an unfinished setup must not put a dead button in
    /// front of anyone.
    @ViewBuilder
    private var backupSection: some View {
        if AppConfig.googleConfigured {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: L("Backup"))

                Text(L("Keep a copy of the people you hold here in your own Google Drive, so a lost phone is not a lost voice."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)

                // Said plainly because "Sign in with Google" sitting next to
                // "give this to the family" reads like the same thing, and
                // someone who believes their sister can now see the archive
                // will not find out otherwise until they need it.
                Text(L("This is not how you give someone to the family — that is the code on their Setup screen. A backup goes to your Drive and nobody else's."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)

                if cloud.isSignedIn {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.sage)
                        Text(cloud.email.isEmpty ? L("Signed in") : cloud.email)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .padding(.top, 4)

                    Button(cloud.working ? L("Working…") : L("Back up now")) {
                        runCloud {
                            let done = try await cloud.backUp(library: library)
                            var lines = [done.sent > 0
                                ? L("Backed up.") + " " + Counts.number(done.sent)
                                : L("Nothing was backed up.")]
                            if done.skipped > 0 {
                                lines.append(L("Some were too large and were left out."))
                            }
                            if done.atRisk > 0 {
                                lines.append(L("Some recordings could not be read, so those people were left as they were rather than overwritten."))
                            }
                            return lines.joined(separator: " ")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(cloud.working)

                    Button(cloud.working ? L("Working…") : L("Bring everything back")) {
                        runCloud {
                            let done = try await cloud.restore(into: library)
                            var lines = [L("Brought back.") + " " + Counts.number(done.brought)]
                            if done.already > 0 {
                                lines.append(L("Some were already here and were left alone."))
                            }
                            if done.failed > 0 {
                                lines.append(L("Some could not be read and were left in Drive."))
                            }
                            return lines.joined(separator: " ")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(cloud.working)

                    Button(L("Sign out of Google")) {
                        cloud.signOut()
                        cloudNote = nil
                        cloudProblem = nil
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .underline()
                    .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
                } else {
                    // Signing in is not only about Drive any more. On a build
                    // that goes through the shared relay, new audio is counted
                    // against an account, so this is the button that allows any
                    // — and the alternative to saying so here is finding out at
                    // the moment of pressing Create, which is the worst
                    // possible time to learn it.
                    if AppConfig.sendsVoiceDeviceHeader {
                        Text(L("Making new audio also needs this. Playing what is already here does not."))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }

                    Button(L("Sign in with Google")) {
                        cloudNote = nil
                        cloudProblem = nil
                        Task {
                            do { try await cloud.signIn() }
                            catch { cloudProblem = (error as? LocalizedError)?.errorDescription }
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                }

                if let cloudNote {
                    Text(cloudNote)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.sage)
                }
                if let cloudProblem {
                    ErrorNote(message: cloudProblem)
                }
            }
            .padding(.top, 20)

            QuietDivider()
        }
    }

    /// One place for the two long-running cloud buttons, so the busy state, the
    /// result line and the failure path cannot drift apart between them.
    @MainActor
    private func runCloud(_ work: @escaping () async throws -> String) {
        cloudNote = nil
        cloudProblem = nil
        Task {
            do { cloudNote = try await work() }
            catch {
                // A cancelled sign-in describes itself as nothing at all, and
                // an empty error note is worse than none.
                cloudProblem = (error as? LocalizedError)?.errorDescription
                    ?? L("That did not work. Try again.")
            }
        }
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
