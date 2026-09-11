import Foundation
import SwiftUI

/// What the person has agreed may leave this phone.
///
/// Jaddati works in two modes and the difference is not cosmetic. Until someone
/// answers the question on the way in, NOTHING is sent anywhere: recordings
/// play, people can be added, the archive works, and no request is made to any
/// server. Answering yes turns on the three features that need a third party.
///
/// Two rules this type exists to enforce, both learned from other people's
/// rejections rather than from our own:
///
/// 1. The gate is shown on `!hasDecided` ALONE. A second condition — a
///    "hasSeenIt" flag, a first-launch check, a build-configuration test —
///    is how an app ships a consent screen that the person reviewing it never
///    sees, and a disclosure nobody saw is not a disclosure.
/// 2. The providers are named in the stored record, not just in the wording on
///    screen. If the app ever sends data somewhere new, `currentTerms` changes,
///    the stored answer no longer matches, and the question is asked again.
///    Consent to send a voice to ElevenLabs is not consent to send it anywhere.
final class Consent: ObservableObject {

    static let shared = Consent()

    /// Bumped whenever the answer would mean something different: a new
    /// provider, a new kind of data, a new purpose. Stored alongside the
    /// answer so an old yes never silently covers a new question.
    ///
    /// Format is deliberately readable in a defaults dump — anyone auditing
    /// this can see what was actually agreed to without reading this file.
    static var currentTerms: String {
        // Derived, not hardcoded. Both hosts are settings read from
        // Secrets.plist, so a build pointed at a relay sends the same audio to
        // a different company — and an agreement naming ElevenLabs is not an
        // agreement covering that. Deriving it means the question is asked
        // again whenever the answer would mean something different.
        let voice = URL(string: AppConfig.voiceBaseURL)?.host ?? "unknown"
        let text = URL(string: AppConfig.llmBaseURL)?.host ?? "unknown"
        return "2026-09-11/\(voice)+\(text)/voice+text+dictation"
    }

    private static let answerKey = "jaddati.consent.answer"
    private static let termsKey  = "jaddati.consent.terms"
    private static let dateKey   = "jaddati.consent.date"

    /// True once the person has answered either way. False means the gate is up.
    @Published private(set) var hasDecided: Bool

    /// True only if they said yes, to these exact terms.
    @Published private(set) var allowsNetwork: Bool

    /// When the answer was given. Shown back to them on the privacy screen so
    /// the record is theirs to inspect, not just ours to hold.
    @Published private(set) var decidedOn: Date?

    private init() {
        let defaults = UserDefaults.standard
        let storedTerms = defaults.string(forKey: Self.termsKey)
        let answered = defaults.object(forKey: Self.answerKey) != nil

        // An answer given to different terms is not an answer to this question.
        let current = answered && storedTerms == Self.currentTerms

        hasDecided = current
        allowsNetwork = current && defaults.bool(forKey: Self.answerKey)
        decidedOn = current ? defaults.object(forKey: Self.dateKey) as? Date : nil
    }

    /// Record an answer. `allowed` false is a real answer, not a deferral —
    /// the app opens in local-only mode and the person is not asked again on
    /// every launch. They can change it on the privacy screen.
    func record(allowed: Bool) {
        let defaults = UserDefaults.standard
        let now = Date()
        defaults.set(allowed, forKey: Self.answerKey)
        defaults.set(Self.currentTerms, forKey: Self.termsKey)
        defaults.set(now, forKey: Self.dateKey)

        hasDecided = true
        allowsNetwork = allowed
        decidedOn = now
    }

    /// The same answer, readable from any thread without touching published
    /// state. The network clients guard on this rather than on `allowsNetwork`
    /// so that a withdrawal made while a request is in flight is seen by the
    /// next call, not by whatever was captured when the view was built.
    static var networkAllowed: Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: termsKey) == currentTerms else { return false }
        return defaults.bool(forKey: answerKey)
    }

    /// Take it back. Guideline 5.1.1(ii) requires this to be as easy to reach
    /// as the original agreement was, and the Program License Agreement
    /// (3.3.3(C)) requires use to stop promptly once it is withdrawn — which
    /// is why every network client checks `allowsNetwork` at call time rather
    /// than reading a copy taken at launch.
    ///
    /// Nothing already on the phone is touched. Withdrawing consent is not the
    /// same as asking for the archive to be deleted, and quietly erasing a
    /// family's recordings because someone tapped the wrong row would be far
    /// worse than the thing this control exists to prevent.
    func withdraw() {
        record(allowed: false)
    }

}

/// Thrown by every client that would put data on the network when the person
/// has not agreed to that.
///
/// This is belt and braces: the interface already hides these features in
/// local-only mode. It exists because a guard at the call site is the only one
/// that cannot be routed around by a screen someone adds later.
struct ConsentMissing: LocalizedError {
    var errorDescription: String? {
        L("This needs to send data to a service outside the phone, and that is currently turned off.")
    }
}
