import SwiftUI

@main
struct JaddatiApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = AudioPlayer()
    @StateObject private var localization = Localization.shared
    @StateObject private var consent = Consent.shared

    init() {
        // Touch it once here, on the main thread, rather than first reading
        // UIDevice from inside a URLSession task.
        _ = AppConfig.deviceId
    }

    /// Shared with YouView by key. "light" unless the user turns it on.
    @AppStorage(Appearance.key) private var appearance: String = Appearance.light

    var body: some Scene {
        WindowGroup {
            Group {
                // One condition, deliberately. The temptation is to add a
                // second — only on first launch, only in release, only if a
                // key is present — and every one of those is a way to ship a
                // disclosure that the person reviewing the app never sees.
                // Until this question is answered it is the whole interface.
                if consent.hasDecided {
                    RootView()
                } else {
                    ConsentGate(consent: consent)
                }
            }
            .environmentObject(library)
            .environmentObject(player)
            .environmentObject(localization)
            .environmentObject(consent)
            // Arabic is a whole interface, not a right-aligned English one.
            // Direction and locale are set together: locale is what makes
            // Intl-style number and date formatting come out in Arabic.
            .environment(\.layoutDirection, localization.language.layoutDirection)
            .environment(\.locale, localization.language.locale)
            // Rebuild the tree outright when the language changes. Without
            // this, screens holding their own @State keep the previous
            // direction and half the app faces the wrong way.
            .id(localization.language)
            .tint(Theme.Palette.wineInk)
            // Dark is a switch in You, not the system's decision. The app
            // opens light because warm paper is the design, so an unset
            // preference means light — hence the explicit scheme rather than
            // leaving it to follow the phone.
            .preferredColorScheme(appearance == "dark" ? .dark : .light)
        }
    }
}

/// One place for the appearance choice, so the switch and the scheme that
/// reads it cannot drift apart over a string literal.
enum Appearance {
    static let key   = "jaddati.appearance"
    static let light = "light"
    static let dark  = "dark"
}
