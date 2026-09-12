import SwiftUI

/// Language as its own screen, reached from You.
///
/// A row that silently flipped the language the instant it was touched gave no
/// sense of what the choice even was. A list shows both, marks the one in use,
/// and makes the change a thing you pick rather than a thing that happens to
/// you. No confirmation here — coming to this screen IS the deliberate act;
/// the globe in the corner is the one that has to ask.
struct LanguageView: View {
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        VStack(spacing: 0) {
            // No globe: it would be a second, quieter control for the one
            // thing this screen exists to do.
            AppBar(title: L("Language"), trailing: AnyView(EmptyView()))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { i, language in
                        if i > 0 { Theme.Palette.hairline.frame(height: 1) }
                        row(language)
                    }

                    SubText(text: L("Arabic lays the whole app out right to left."))
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
    }

    private func row(_ language: AppLanguage) -> some View {
        let current = localization.language == language
        return Button {
            guard !current else { return }
            localization.language = language
        } label: {
            HStack(spacing: 14) {
                // The name is written in its own language, so it reads the way
                // someone looking for it would recognise it.
                BidiText(value: language.endonym,
                         font: Theme.Font.displayMedium(19),
                         colour: Theme.Palette.ink)
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.wineInk)
                }
            }
            .frame(minHeight: Theme.Metric.touchTarget)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }
}
