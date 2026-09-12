import SwiftUI

/// The shell. People, Letters and You are the three places you can be, and the
/// rail is visible from all of them.
///
/// All three work with nothing in the app yet. The two they replaced did not:
/// Saved and Books were scoped to a person, so opening the app and tapping
/// either one answered "Choose someone first". Saved and Books are now doors
/// on the person screen, where the person they belong to is already known.
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

                NavigationStack { AllLettersView().swipeBackEnabled() }
                    .tag(RootTab.letters)

                NavigationStack { YouView().swipeBackEnabled() }
                    .tag(RootTab.you)
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
}
