import SwiftUI
import UIKit

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

    private func applyWindowAppearance() {
        let style: UIUserInterfaceStyle = appearance == Appearance.dark ? .dark : .light
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

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
            //
            // The appearance is part of the identity for the same reason. A
            // Color built from a dynamic UIColor can be held by SwiftUI after
            // it has been resolved once, and a half-repainted screen is worse
            // than no toggle at all.
            .id("\(localization.language)-\(appearance)")
            .tint(Theme.Palette.wineInk)
            // Dark is a switch in You, not the system's decision. The app
            // opens light because warm paper is the design, so an unset
            // preference means light — hence the explicit scheme rather than
            // leaving it to follow the phone.
            .preferredColorScheme(appearance == Appearance.dark ? .dark : .light)
            // And this, which is the part that actually mattered.
            //
            // preferredColorScheme sets SwiftUI's ENVIRONMENT. Every colour in
            // the palette is a dynamic UIColor, and those resolve against
            // UITraitCollection.current — the WINDOW's appearance. Inside the
            // safe area SwiftUI keeps the two in step; for anything that
            // escapes it, notably the tab rail's ground and the status bar,
            // it does not. The result was one half of the screen asking the
            // environment and the other half asking the phone, on a screen
            // where both grounds are the same token.
            //
            // Setting the window's own style leaves one answer for every path
            // to find.
            .onAppear { applyWindowAppearance() }
            .onChange(of: appearance) { _, _ in applyWindowAppearance() }
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
