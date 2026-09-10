import SwiftUI

/// Everything kept for one person, originals and generated together, always
/// distinguishable at a glance — and filterable by the experience that made it,
/// so a comfort line saved last week is findable without scrolling past
/// everything else.
struct MemoriesView: View {
    let personId: UUID
    @State private var filter: Filter

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @State private var opened: AudioAsset?

    init(personId: UUID, filter: Filter = .all) {
        self.personId = personId
        _filter = State(initialValue: filter)
    }

    enum Filter: Hashable, CaseIterable {
        case all, original, recreated, saySomething, comfort, stories, memories

        var title: String {
            switch self {
            case .all:          return "All"
            case .original:     return "Their voice"
            case .recreated:    return "Recreated"
            case .saySomething: return "Said"
            case .comfort:      return "Comfort"
            case .stories:      return "Stories"
            case .memories:     return "Memories"
            }
        }

        /// The intent this filter narrows to, if it narrows to one.
        var intent: Intent? {
            switch self {
            case .saySomething: return .saySomething
            case .comfort:      return .comfort
            case .stories:      return .storyFiction
            case .memories:     return .storyFromMemories
            default:            return nil
            }
        }
    }

    private var person: Person? { library.person(withId: personId) }

    private var items: [AudioAsset] {
        guard let person else { return [] }
        // Unkept drafts stay hidden; originals are always kept.
        let all = library.assets(for: person)
            .filter { $0.source == .original || $0.isSaved }
        switch filter {
        case .all:       return all
        case .original:  return all.filter { $0.source == .original }
        case .recreated: return all.filter { $0.source == .generated }
        default:
            guard let wanted = filter.intent else { return all }
            return all.filter { $0.intentRaw == wanted.rawValue }
        }
    }

    /// Only offer a filter that would show something.
    private var availableFilters: [Filter] {
        guard let person else { return [.all] }
        let all = library.assets(for: person).filter { $0.source == .original || $0.isSaved }
        return Filter.allCases.filter { candidate in
            switch candidate {
            case .all:       return true
            case .original:  return all.contains { $0.source == .original }
            case .recreated: return all.contains { $0.source == .generated }
            default:
                guard let wanted = candidate.intent else { return false }
                return all.contains { $0.intentRaw == wanted.rawValue }
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    filterRow

                    if items.isEmpty {
                        EmptyHint(icon: "tray",
                                  title: "Nothing here yet",
                                  message: "Anything you keep will be waiting here, and it plays without a connection.")
                    } else {
                        // Deliberately NOT a NavigationLink wrapping the row:
                        // AudioRow contains its own play button, and a button
                        // inside a link label loses its taps to the link.
                        ForEach(items) { asset in
                            AudioRow(asset: asset) { opened = asset }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if player.playingAssetId == asset.id { player.stop() }
                                        library.delete(asset)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle(person?.name ?? "Memories")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { asset in
            PlayerView(asset: asset)
        }
        .onChange(of: availableFilters) { _, now in
            // Deleting the last clip of a kind removes its chip. Without this
            // the selection sticks to a chip that is no longer on screen and
            // the list reads as empty for no visible reason.
            if !now.contains(filter) { filter = .all }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(availableFilters, id: \.self) { candidate in
                    Button { filter = candidate } label: {
                        Text(candidate.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(filter == candidate
                                             ? Theme.Palette.ivory : Theme.Palette.forest)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(filter == candidate
                                               ? Theme.Palette.forest : Theme.Palette.ivorySunk)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
