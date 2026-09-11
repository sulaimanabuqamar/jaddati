import SwiftUI

/// The first thing anyone sees, until they answer it.
///
/// Three features in this app send something off the phone, and two of them —
/// questions during a story, and speaking instead of typing — used to do it
/// with no disclosure at all. That is the single most common reason an app
/// like this one is rejected, and the wording of the rejection is specific:
/// say what is sent, say who it is sent to, and ask before sending it.
///
/// So this screen names both companies, names the three kinds of data, and
/// does not let itself be skipped. The alternative is not "quit" — it is a
/// working app that keeps everything on the phone, which is also the honest
/// answer to someone who does not want their family's voice on a server.
struct ConsentGate: View {
    @ObservedObject var consent: Consent
    @State private var showingDetail = false

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    header
                    whatIsSent
                    Group {
                        choices
                        footnote
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .sheet(isPresented: $showingDetail) {
            PrivacyScreen(consent: consent, showsControls: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            // The globe has to be here. Every other way to change language sits
            // behind this screen, and the app opens in English — so without it
            // an Arabic reader meets a consent question they may not be able to
            // read, which is not consent.
            HStack {
                Eyebrow(text: L("Before you begin"))
                Spacer(minLength: 0)
                // AppBar gives the globe a full touch target; bare, it is the
                // 36pt drawn circle, which is under the minimum.
                GlobeButton()
                    .frame(width: Theme.Metric.touchTarget,
                           height: Theme.Metric.touchTarget)
            }
            Headline(text: L("Some of this\nleaves the phone."), size: 33)
            SubText(text: L("Jaddati can work entirely on this phone. Three things cannot, because they are done by companies outside it. Here is exactly what they are."))
        }
    }

    private var whatIsSent: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                recipient(
                    name: AppConfig.voiceProviderName,
                    role: L("Voice service"),
                    sends: L("The recording you choose, and the words you ask to be spoken."),
                    why: L("It builds the voice and reads your words in it. The voice it builds is kept on their servers, not only here.")
                )

                Divider().overlay(Theme.Palette.hairline)

                recipient(
                    name: AppConfig.textProviderName,
                    role: L("Questions and dictation"),
                    sends: L("A question typed or spoken during a story, with the page it is about — and the audio itself when you speak instead of typing."),
                    why: L("It writes the answer, and turns speech into text. It is never told whose voice will read the answer out.")
                )
            }
        }
    }

    private func recipient(name: String, role: String, sends: String, why: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Text(name)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Text("·")
                    .foregroundStyle(Theme.Palette.hairline)
                Text(role)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }

            labelled(L("What is sent"), sends)
            labelled(L("What they do with it"), why)
        }
    }

    private func labelled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(uiIsArabic ? 0 : 0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.wine)
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(Theme.textLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var choices: some View {
        VStack(spacing: Theme.Space.s) {
            Button(L("Allow these three things")) {
                consent.record(allowed: true)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(L("Not now — keep everything on this phone")) {
                consent.record(allowed: false)
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(L("Choosing to keep everything here still opens the app. You can play recordings, add people, and keep an archive. Creating a new voice, asking questions and speaking instead of typing stay switched off until you change this."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(Theme.textLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            Button(L("Read the full privacy notice")) { showingDetail = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.wine)
                .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
        }
    }
}

/// The privacy notice, in the app.
///
/// Guideline 5.1.1(i) asks for this to be reachable inside the app and not
/// only as a link in the store listing, and to cover four things: what is
/// collected, how, what it is used for, and how someone gets it deleted. The
/// Program License Agreement (3.3.3(C)) adds retention and sharing to that
/// list. Each of those has its own block below rather than being folded into
/// a paragraph, because a reviewer is looking for them one at a time.
struct PrivacyScreen: View {
    @ObservedObject var consent: Consent
    /// False when this is shown from inside the gate — the decision is made
    /// with the buttons behind it, not twice.
    var showsControls: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Headline(text: L("What Jaddati\ndoes with data."), size: 30)
                        staysHere
                        leavesHere
                        keptAndDeleted
                        if showsControls { controls }
                        contact
                    }
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.vertical, Theme.Space.m)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close")) { dismiss() }
                }
                // No globe here. Switching language changes the .id on the
                // root, which tears the tree down and takes this sheet with
                // it — the control added so an Arabic reader could read the
                // notice would close the notice. The globe on the screen
                // behind this one does the job without that.
            }
        }
    }

    private var staysHere: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(text: L("Stays on this phone"))
                bullet(L("Recordings you add, and every clip the app creates."))
                bullet(L("Names, relationships and photos."))
                bullet(L("Which language you read the app in."))
                Text(L("These are held in the app's own storage. There is no account, and Jaddati has no server of its own — nothing here is uploaded to us, because there is no us to upload it to."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineSpacing(Theme.textLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var leavesHere: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(text: L("Sent to others, only if you allow it"))
                bullet(L("ElevenLabs receives the recording you choose and the words you want spoken. The voice it builds is stored under this app's account there."))
                bullet(L("Groq receives a question and the page it is about, and the audio when you speak instead of typing."))
                bullet(L("When Jaddati reaches these services through a relay we run, requests carry a code identifying this phone, so one phone cannot use up everyone's allowance. It is not a name, is not linked to one, and is not sent when the app calls the two services directly."))
                Text(L("Both are bound by their own terms, which require them to protect what they are sent. Jaddati does not send them anything else, and does not send anything anywhere else."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineSpacing(Theme.textLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var keptAndDeleted: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(text: L("Keeping and deleting"))
                bullet(L("Deleting a person here deletes their recordings and clips from this phone straight away."))
                bullet(L("Removing the app removes all of it."))
                bullet(L("Removing a person also deletes the voice built for them at the voice service. That happens first, and if it fails nothing here is removed, so it can be tried again."))
                bullet(L("Neither service is asked to keep anything for Jaddati, and Jaddati keeps no copy of what it sends."))
            }
        }
    }

    private var controls: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel(text: L("Your answer"))

                Text(statusLine)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if consent.allowsNetwork {
                    Button(L("Stop sending anything off this phone")) { consent.withdraw() }
                        .buttonStyle(QuietButtonStyle())
                } else {
                    Button(L("Allow the three things above")) { consent.record(allowed: true) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var statusLine: String {
        let answer = consent.allowsNetwork
            ? L("You allowed the app to use the two services above.")
            : L("Everything is being kept on this phone. Nothing is sent anywhere.")
        guard let date = consent.decidedOn else { return answer }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Localization.shared.language.locale)
        let stamp = date.formatted(style)
        // The full stop rides inside the localized fragment: a trailing ASCII
        // period after a Latin date inside an Arabic paragraph lands at the
        // wrong end of the line.
        return answer + " " + L("You chose this on") + " " + stamp
    }

    private var contact: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Questions about any of this"))
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.ink)
            Text(verbatim: "sulaiman.abuqamar@gmail.com")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.wine)
                .textSelection(.enabled)
            Text(verbatim: "sulaimanabuqamar.github.io/jaddati/privacy")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .textSelection(.enabled)
        }
        .padding(.top, Theme.Space.xs)
    }

    private func bullet(_ words: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Circle()
                .fill(Theme.Palette.wine)
                .frame(width: 4, height: 4)
                .padding(.top, 8)
            Text(words)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(Theme.textLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
