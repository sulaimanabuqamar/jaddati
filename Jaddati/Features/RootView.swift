import SwiftUI

/// The shell. People, Saved and Books are the three places you can be, and the
/// rail is visible from all of them.
///
/// Saved and Books are scoped to one person — a pile of clips with no name on
/// it is not an archive. Opening someone from People selects them, and the
/// other two tabs carry a breadcrumb saying whose they are.
struct RootView: View {
    @EnvironmentObject private var library: Library
    @State private var tab: RootTab = .people
    @State private var selectedPersonId: UUID?

    private var selectedPerson: Person? {
        if let selectedPersonId, let found = library.person(withId: selectedPersonId) { return found }
        return library.people.count == 1 ? library.people.first : nil
    }

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .people:
                        HomeView(selectedPersonId: $selectedPersonId)
                    case .saved:
                        personScoped { person in
                            MemoriesView(personId: person.id)
                        } emptyTitle: {
                            L("Open a person to see what is kept for them.")
                        }
                    case .books:
                        personScoped { person in
                            BooksView(personId: person.id)
                        } emptyTitle: {
                            L("Open a person to bring them a text.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabRail(selection: $tab)
            }
        }
        .onChange(of: selectedPersonId) { _, id in
            // Opening someone is what selects them; the other tabs follow.
            if id != nil, tab == .people { return }
        }
    }

    @ViewBuilder
    private func personScoped<Content: View>(
        @ViewBuilder _ content: (Person) -> Content,
        emptyTitle: () -> String
    ) -> some View {
        if let person = selectedPerson {
            NavigationStack { content(person) }
        } else {
            VStack(spacing: 0) {
                AppBar(title: L("Jaddati"))
                EmptyHint(icon: "person.crop.circle",
                          title: L("Choose someone first"),
                          message: emptyTitle())
                Spacer()
            }
        }
    }
}
