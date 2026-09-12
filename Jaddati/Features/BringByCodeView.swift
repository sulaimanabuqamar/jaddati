import SwiftUI

/// Typing in the code someone read out to you.
///
/// This used to be a file picker, which meant the archive had to be found,
/// attached, sent, found again and opened — five places a family can lose her,
/// and the first four happen on a phone while someone stands next to you
/// waiting. Six characters is the whole of it now.
///
/// The file has not gone anywhere. A code needs the internet and stops at a
/// size the file does not, so the way out is at the bottom of this screen
/// rather than somewhere to go looking for.
struct BringByCodeView: View {
    var onArrived: (Archive.ImportResult) -> Void
    var onWantsFile: () -> Void

    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var looking = false
    @State private var problem: String?

    /// Read aloud, so accept it typed back however it arrives — lower case,
    /// spaces, the lot.
    private var code: String { Archive.tidy(typed) }
    private var ready: Bool { code.count == 6 && !looking }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Bring someone from another phone"),
                   showsBack: false,
                   trailing: AnyView(
                       Button { dismiss() } label: {
                           Image(systemName: "xmark")
                               .font(.system(size: 15, weight: .semibold))
                               .foregroundStyle(Theme.Palette.ink)
                               .frame(width: Theme.Metric.touchTarget,
                                      height: Theme.Metric.touchTarget)
                               .contentShape(Rectangle())
                       }
                       .accessibilityLabel(L("Cancel"))))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SubText(text: L("On the phone that has them, open that person, tap the gear, and choose Give this to the family. Type the code it shows here."))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Their code"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                        TextField("K7M2Q4", text: $typed)
                            .font(Theme.Font.displayMedium(26))
                            .kerning(6)
                            .multilineTextAlignment(.center)
                            // Latin whichever language the app is in, so it
                            // must not mirror with the rest of the screen.
                            .environment(\.layoutDirection, .leftToRight)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius)
                                    .fill(Theme.Palette.card)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius)
                                        .stroke(Theme.Palette.hairline, lineWidth: 1))
                            )
                    }

                    if let problem {
                        ErrorNote(message: problem)
                    }

                    Button(looking ? L("Looking…") : L("Bring them in")) {
                        Task { await bring() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!ready)

                    Theme.Palette.hairline.frame(height: 1).padding(.top, 8)

                            // The flag goes up BEFORE the dismiss, and the parent
                    // opens the picker once this sheet has actually gone.
                    // Asking for it straight after dismiss() asked SwiftUI to
                    // present while it was still tearing down, and the picker
                    // simply never appeared.
                    Button(L("Bring them in from a file instead")) {
                        onWantsFile()
                        dismiss()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .underline()
                    .frame(minHeight: Theme.Metric.touchTarget, alignment: .leading)
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
    }

    @MainActor
    private func bring() async {
        looking = true
        problem = nil
        defer { looking = false }
        do {
            let brought = try await Archive.fetch(code: code, into: library)
            onArrived(brought)
            dismiss()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription
                ?? L("That code could not be checked. Try again.")
        }
    }
}
