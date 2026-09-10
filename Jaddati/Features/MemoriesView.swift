import SwiftUI

/// Everything kept for one person, originals and generated together, always
/// distinguishable at a glance.
struct MemoriesView: View {
    let personId: UUID

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable {
        case all = "All"
        case original = "Their voice"
        case generated = "Recreated"
    }

    private var person: Person? { library.person(withId: personId) }

    private var items: [AudioAsset] {
        guard let person else { return [] }
        switch filter {
        case .all:       return library.assets(for: person)
        case .original:  return library.assets(for: person, source: .original)
        case .generated: return library.assets(for: person, source: .generated)
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
                        ForEach(items) { asset in
                            NavigationLink {
                                PlayerView(asset: asset)
                            } label: {
                                AudioRow(asset: asset)
                            }
                            .buttonStyle(.plain)
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
    }
}
