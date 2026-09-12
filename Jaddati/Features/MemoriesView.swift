import SwiftUI

/// Everything kept for one person, originals and generated together, always
/// distinguishable at a glance.
///
/// Origin and experience are two different questions — "was this really them?"
/// and "which screen made it?" — so they are two independent controls. The one
/// long strip they replaced forced a choice between them and made it impossible
/// to ask for, say, every recreated bedtime story.
struct MemoriesView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @State private var opened: AudioAsset?
    @State private var pendingDeletion: AudioAsset?
    @State private var origin: OriginFilter = .all
    @State private var experience: ExperienceFilter = .all

    /// Kept so callers that opened this screen pre-filtered still compile and
    /// still land where they meant to.
    enum Filter: Hashable { case all, original, recreated }

    /// True when this is the Saved tab itself rather than a push from a person,
    /// so the tab root does not draw a chevron that goes nowhere.
    let isTabRoot: Bool

    init(personId: UUID, filter: Filter = .all, isTabRoot: Bool = false) {
        self.personId = personId
        self.isTabRoot = isTabRoot
        switch filter {
        case .all:       _origin = State(initialValue: .all)
        case .original:  _origin = State(initialValue: .original)
        case .recreated: _origin = State(initialValue: .recreated)
        }
    }

    enum OriginFilter: Hashable, CaseIterable {
        case all, original, recreated
        var title: String {
            switch self {
            case .all:       return L("All")
            case .original:  return L("Original recording")
            case .recreated: return L("AI recreated")
            }
        }
        func matches(_ asset: AudioAsset) -> Bool {
            switch self {
            case .all:       return true
            case .original:  return asset.source == .original
            case .recreated: return asset.source == .generated
            }
        }
    }

    enum ExperienceFilter: Hashable, CaseIterable {
        case all, saySomething, asked, across, comfort, story, kept, book
        var title: String {
            switch self {
            case .all:  return L("All")
            case .saySomething: return Intent.saySomething.title
            case .asked:        return Intent.askAboutThem.title
            case .across:       return Intent.bridgeLanguage.title
            case .comfort:      return Intent.comfort.title
            case .story:        return Intent.storyFiction.title
            case .kept:         return Intent.storyFromMemories.title
            case .book:         return Intent.readBook.title
            }
        }
        var intent: Intent? {
            switch self {
            case .all:          return nil
            case .saySomething: return .saySomething
            case .asked:        return .askAboutThem
            case .across:       return .bridgeLanguage
            case .comfort:      return .comfort
            case .story:        return .storyFiction
            case .kept:         return .storyFromMemories
            case .book:         return .readBook
            }
        }
        func matches(_ asset: AudioAsset) -> Bool {
            guard let wanted = intent else { return true }
            return asset.intentRaw == wanted.rawValue
        }
    }

    private var person: Person? { library.person(withId: personId) }

    /// Unkept drafts stay hidden; originals are always kept.
    private var everything: [AudioAsset] {
        guard let person else { return [] }
        return library.archive(for: person)
    }

    private var items: [AudioAsset] {
        everything.filter { origin.matches($0) && experience.matches($0) }
    }

    private var isFiltered: Bool { origin != .all || experience != .all }

    /// Only offer a control that would change anything.
    private var availableOrigins: [OriginFilter] {
        OriginFilter.allCases.filter { candidate in
            candidate == .all || everything.contains { candidate.matches($0) }
        }
    }

    private var availableExperiences: [ExperienceFilter] {
        ExperienceFilter.allCases.filter { candidate in
            candidate == .all || everything.contains { candidate.matches($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppBar(title: L("Saved"), showsBack: !isTabRoot)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let person {
                        Breadcrumb(name: person.name,
                                   relationship: person.relationship,
                                   photo: library.photoURL(for: person))
                        Headline(text: L("Carefully kept."))
                        SubText(text: L("Original recordings and the new words you chose to save."))
                    }

                    if availableOrigins.count > 2 {
                        filterRow(L("Origin"), availableOrigins, selected: origin) { candidate in
                            origin = candidate
                            if candidate == .original { experience = .all }
                        }
                    }
                    // Hidden when the origin is set to real recordings: those
                    // are stored with no experience, so every chip but All
                    // would be guaranteed empty and still tappable.
                    if origin != .original, availableExperiences.count > 2 {
                        filterRow(L("Experience"), availableExperiences, selected: experience) { experience = $0 }
                    }

                    if items.isEmpty {
                        emptyState
                    } else {
                        // Deliberately NOT a NavigationLink wrapping the row:
                        // AudioRow contains its own play button, and a button
                        // inside a link label loses its taps to the link.
                        ForEach(items) { asset in
                            AudioRow(asset: asset) { opened = asset }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDeletion = asset
                                    } label: {
                                        Label(asset.source == .original
                                              ? L("Delete this recording")
                                              : L("Delete clip"),
                                              systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .navigationDestination(item: $opened) { asset in
            PlayerView(asset: asset)
        }
        // An original recording is the one thing here that cannot be made
        // again, so the wording changes with what is about to go.
        .confirmationDialog(pendingDeletion?.source == .original
                            ? L("Delete this recording?")
                            : L("Discard this clip?"),
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button(L("Delete permanently"), role: .destructive) {
                if let asset = pendingDeletion {
                    if player.playingAssetId == asset.id { player.stop() }
                    library.delete(asset)
                }
                pendingDeletion = nil
            }
            Button(L("Cancel"), role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion?.source == .original
                 ? L("This is a real recording of them and the only copy on this phone. It cannot be recovered.")
                 : L("The audio is deleted from this phone. Creating it again costs credits."))
        }
        .onChange(of: everything.count) { _, _ in
            // Deleting the last clip of a kind removes its chip. Without this
            // the selection sticks to a chip that is no longer on screen and
            // the list reads as empty for no visible reason.
            if !availableOrigins.contains(origin) { origin = .all }
            if !availableExperiences.contains(experience) { experience = .all }
        }
    }

    /// An empty list means two different things, and saying the wrong one is a
    /// lie about the person's collection.
    @ViewBuilder private var emptyState: some View {
        if isFiltered {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                EmptyHint(icon: "line.3.horizontal.decrease.circle",
                          title: L("No clips match this filter"),
                          message: activeFilterSummary)
                Button(L("Clear filters")) {
                    origin = .all
                    experience = .all
                }
                .buttonStyle(QuietButtonStyle())
                .frame(maxWidth: .infinity)
            }
        } else {
            EmptyHint(icon: "tray",
                      title: L("Nothing saved yet"),
                      message: L("Clips you choose to keep will appear here."))
        }
    }

    private var activeFilterSummary: String {
        var parts: [String] = []
        if origin != .all { parts.append(L("Origin") + ": " + origin.title) }
        if experience != .all { parts.append(L("Experience") + ": " + experience.title) }
        return parts.joined(separator: " · ") + "\n" + L("Try another filter or show all clips.")
    }

    private func filterRow<F: Hashable>(_ label: String,
                                        _ options: [F],
                                        selected: F,
                                        choose: @escaping (F) -> Void) -> some View
    where F: FilterChip {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(options, id: \.self) { candidate in
                        let isOn = candidate == selected
                        Button { choose(candidate) } label: {
                            Text(candidate.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isOn ? Theme.Palette.ivory : Theme.Palette.wineInk)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(
                                    Capsule().fill(isOn ? Theme.Palette.forest
                                                        : Theme.Palette.ivorySunk)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label + ", " + candidate.title)
                        .accessibilityAddTraits(isOn ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

/// Lets one generic chip row serve both filter dimensions.
protocol FilterChip: Hashable {
    var title: String { get }
}

extension MemoriesView.OriginFilter: FilterChip {}
extension MemoriesView.ExperienceFilter: FilterChip {}
