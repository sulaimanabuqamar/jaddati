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
                            MemoriesView(personId: person.id, isTabRoot: true)
                        } emptyMessage: {
                            L("Open a person to see what is kept for them.")
                        }
                    case .books:
                        personScoped { person in
                            BooksView(personId: person.id, isTabRoot: true)
                        } emptyMessage: {
                            L("Open a person to bring them a text.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabRail(selection: $tab)
            }
            // The rail is furniture, not content. Without this it rides up with
            // the keyboard and covers the line being typed.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// Saved and Books both need a person. When there is not one the screen says
    /// so AND offers the way out — this used to be a sentence with no control
    /// under it, on a tab the user had just deliberately chosen.
    @ViewBuilder
    private func personScoped<Content: View>(
        @ViewBuilder _ content: (Person) -> Content,
        emptyMessage: () -> String
    ) -> some View {
        if let person = selectedPerson {
            NavigationStack { content(person) }
        } else {
            VStack(spacing: 0) {
                AppBar(title: L("Jaddati"), showsBack: false)
                Spacer(minLength: 0)
                EmptyHint(icon: "person.crop.circle",
                          title: L("Choose someone first"),
                          message: emptyMessage())
                Button(L("Go to People")) { tab = .people }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, Theme.Space.s)
                Spacer(minLength: 0)
            }
        }
    }
}
