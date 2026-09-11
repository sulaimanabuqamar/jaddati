import SwiftUI

/// The shell. People, Saved and Books are the three places you can be, and the
/// rail is visible from all of them.
///
/// Saved and Books are scoped to one person — a pile of clips with no name on
/// it is not an archive. Opening someone from People selects them, and the
/// other two tabs carry a breadcrumb saying whose they are.
struct RootView: View {
    @EnvironmentObject private var library: Library

    // Switching language rebuilds the whole tree by design (JaddatiApp puts an
    // .id on it), which used to throw away the chosen tab and the chosen person
    // as well — tap the globe while reading a book and you landed back on
    // People. These outlive the rebuild; only the push stack is lost.
    @AppStorage("jaddati.tab") private var storedTab: String = RootTab.people.rawValue
    @AppStorage("jaddati.person") private var storedPerson: String = ""

    private var tab: Binding<RootTab> {
        Binding(get: { RootTab(rawValue: storedTab) ?? .people },
                set: { storedTab = $0.rawValue })
    }

    private var selectedPersonId: Binding<UUID?> {
        Binding(get: { storedPerson.isEmpty ? nil : UUID(uuidString: storedPerson) },
                set: { storedPerson = $0?.uuidString ?? "" })
    }

    private var selectedPerson: Person? {
        if let id = selectedPersonId.wrappedValue,
           let found = library.person(withId: id) { return found }
        return library.people.count == 1 ? library.people.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // A pager, not a switch. Three reasons: you can swipe between
            // the tabs the way every other app on the phone lets you; the
            // change is animated, so it reads as movement rather than as
            // the screen being replaced; and all three stay alive, so a tab
            // still remembers where you were when you come back to it. The
            // switch it replaced tore down the navigation stack every time.
            TabView(selection: tab) {
                HomeView(selectedPersonId: selectedPersonId)
                    .tag(RootTab.people)

                personScoped { person in
                    MemoriesView(personId: person.id, isTabRoot: true)
                } emptyMessage: {
                    L("Open a person to see what is kept for them.")
                }
                .tag(RootTab.saved)

                personScoped { person in
                    BooksView(personId: person.id, isTabRoot: true)
                } emptyMessage: {
                    L("Open a person to bring them a text.")
                }
                .tag(RootTab.books)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabRail(selection: tab)
        }
        // The ground, as a background rather than as a sibling in a ZStack. A
        // sibling that ignores the safe area can hand its expanded frame to the
        // stack, and screens started drawing up underneath the status bar.
        .background(Theme.Palette.paper.ignoresSafeArea())
        // The rail is furniture, not content. Without this it rides up with the
        // keyboard and covers the line being typed.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: library.people.count) { _, _ in forgetSelectionIfGone() }
        .onAppear(perform: forgetSelectionIfGone)
    }

    /// A deleted person left their id selected. With one person remaining the
    /// fallback silently re-pointed Saved and Books at whoever was left — and
    /// the id now survives a relaunch, so it has to be checked on the way in.
    private func forgetSelectionIfGone() {
        guard let id = selectedPersonId.wrappedValue,
              library.person(withId: id) == nil else { return }
        selectedPersonId.wrappedValue = nil
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
            NavigationStack { content(person).swipeBackEnabled() }
        } else {
            VStack(spacing: 0) {
                AppBar(title: tab.wrappedValue.title, showsBack: false)
                Spacer(minLength: 0)
                EmptyHint(icon: "person.crop.circle",
                          title: L("Choose someone first"),
                          message: emptyMessage())
                Button(L("Go to People")) { tab.wrappedValue = .people }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, Theme.Space.s)
                Spacer(minLength: 0)
            }
        }
    }
}
