import SwiftUI

@main
struct JaddatiApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
                .environmentObject(player)
                .tint(Theme.Palette.forest)
                .preferredColorScheme(.light)
        }
    }
}
