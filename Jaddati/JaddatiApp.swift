import SwiftUI

@main
struct JaddatiApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = AudioPlayer()
    @StateObject private var localization = Localization.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(localization)
                // Arabic is a whole interface, not a right-aligned English one.
                // Direction and locale are set together: locale is what makes
                // Intl-style number and date formatting come out in Arabic.
                .environment(\.layoutDirection, localization.language.layoutDirection)
                .environment(\.locale, localization.language.locale)
                // Rebuild the tree outright when the language changes. Without
                // this, screens holding their own @State keep the previous
                // direction and half the app faces the wrong way.
                .id(localization.language)
                .tint(Theme.Palette.forest)
                .preferredColorScheme(.light)
        }
    }
}
