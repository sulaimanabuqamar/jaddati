import SwiftUI

/// Everything kept for one person, originals and generated together, always
/// distinguishable at a glance.
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

    enum Filter: String, CaseIterable {
        case all = "All"
        case original = "Their voice"
        case generated = "Recreated"
    }

    private var person: Person? { library.person(withId: personId) }

    private var items: [AudioAsset] {
        guard let person else { return [] }
        let all = library.assets(for: person)
            .filter { $0.source == .original || $0.isSaved }   // unkept drafts stay hidden
        switch filter {
        case .all:       return all
        case .original:  return all.filter { $0.source == .original }
        case .generated: return all.filter { $0.source == .generated }
        }
    }

    var body: some View {
        ZStack {
            Theme.Palette.ivory.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

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
    }
}
