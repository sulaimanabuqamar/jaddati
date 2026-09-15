import SwiftUI

/// Every letter, across everyone.
///
/// The only part of this app that is about a DATE rather than about a person,
/// which is exactly why it earns a tab of its own. A letter whose day has come
/// has to find you without your having remembered whose it was — sitting one
/// level down inside whichever person you happened to open is how a sealed
/// letter quietly never arrives.
struct AllLettersView: View {
    /// A Button and a destination, not a NavigationLink. SwiftUI will decide,
    /// on some phones and not others, that it is not going to push a
    /// destination link inside a stack that also pushes by value — and a link
    /// it will not push it draws DISABLED and swallows the tap, with nothing
    /// in the project asking for that. Every push in this app is explicit now.
    @State private var opening: UUID?

    @EnvironmentObject private var library: Library
    @ObservedObject private var localization = Localization.shared

    private struct Entry: Identifiable {
        let person: Person
        let letter: Letter
        var id: UUID { letter.id }
    }

    /// Soonest first, so what is closest to arriving reads first.
    private var entries: [Entry] {
        library.letters
            .compactMap { letter in
                guard let person = library.person(withId: letter.personId) else { return nil }
                return Entry(person: person, letter: letter)
            }
            .sorted { $0.letter.deliverAt < $1.letter.deliverAt }
    }

    private var due: [Entry] { entries.filter { $0.letter.isDue } }
    private var sealed: [Entry] { entries.filter { $0.letter.isSealed } }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Letters"), showsBack: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if library.people.isEmpty {
                        EmptyHint(icon: "lock",
                                  title: L("No letters yet"),
                                  message: L("Words you seal now and hear on a day you choose."))
                    } else if due.isEmpty && sealed.isEmpty {
                        EmptyHint(icon: "lock",
                                  title: L("No letters yet"),
                                  message: L("Open someone and write words for a day that has not come yet."))
                    } else {
                        if !due.isEmpty {
                            SectionLabel(text: L("Waiting for you"))
                                .padding(.top, 22)
                            ForEach(due) { row($0, isDue: true) }
                        }
                        if !sealed.isEmpty {
                            SectionLabel(text: L("Sealed"))
                                .padding(.top, due.isEmpty ? 22 : 26)
                            ForEach(sealed) { row($0, isDue: false) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .navigationDestination(item: $opening) { id in
            LettersView(personId: id)
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry, isDue: Bool) -> some View {
        Button {
            opening = entry.person.id
        } label: {
            HStack(spacing: 14) {
                PersonAvatar(name: entry.person.name,
                             imageURL: library.photoURL(for: entry.person),
                             size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    BidiText(value: entry.letter.occasion.isEmpty
                             ? L("A letter") : entry.letter.occasion)
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(entry.person.name + " · " + Self.dateText(entry.letter.deliverAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isDue {
                    Text(L("Ready"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.paper)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.Palette.danger))
                } else {
                    Image(systemName: "lock")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .frame(minHeight: Theme.Metric.touchTarget)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: uiIsArabic ? "ar" : "en")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
