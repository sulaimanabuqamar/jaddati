import Foundation

/// Where the app gets its provider credentials and defaults.
///
/// The key is read from `Secrets.plist`, which is git-ignored and never
/// committed. It is NOT in source control. It IS in the app bundle on the
/// phone, which is a development shortcut, not a shipping design — see
/// README "Known limitations". The `VoiceService` protocol exists so a server
/// proxy can replace the direct client without touching any view.
enum AppConfig {

    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data,
                                                                    options: [],
                                                                    format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }()

    /// Empty string when unset — the app degrades to a clear "not configured"
    /// state rather than crashing or pretending to work.
    static var elevenLabsKey: String {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty {
            return env
        }
        return (secrets["ELEVENLABS_API_KEY"] as? String) ?? ""
    }

    static var isConfigured: Bool { !elevenLabsKey.isEmpty }

    /// Arabic-capable and stable on long-form. Confirmed present in the
    /// ElevenLabs model list; the spike prints what this account can reach.
    static let defaultModelId = "eleven_multilingual_v2"

    /// Half the price and much lower latency. Offered as an option once we
    /// have measured both against a real cloned voice.
    static let fastModelId = "eleven_flash_v2_5"

    /// Hard ceiling per generation. Guards against a runaway request eating
    /// the month's credits — the plan has no automatic overage, so the real
    /// risk is wasted credits, not a surprise bill.
    static let maxCharactersPerGeneration = 800

    /// Network calls give up rather than hanging a screen forever.
    static let requestTimeout: TimeInterval = 45
}
