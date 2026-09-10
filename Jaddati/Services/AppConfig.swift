import Foundation

/// Where the app gets its provider credentials and defaults.
///
/// The key is read from `Secrets.plist`, which is git-ignored and never
/// committed. It is NOT in source control. It IS in the app bundle on the
/// phone, which is a development shortcut, not a shipping design — see
/// README "Known limitations".
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

    static var elevenLabsKey: String {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty {
            return env
        }
        let value = (secrets["ELEVENLABS_API_KEY"] as? String) ?? ""
        return value == "PASTE_YOUR_KEY_HERE" ? "" : value
    }

    /// Key for the debug-only offline mode. Never consulted in a Release build.
    static let mockDefaultsKey = "jaddati.useMockVoices"

    /// Voice ids minted by the offline test mode carry this prefix. They exist
    /// only inside that mode; against the live service they are meaningless.
    /// Defined here rather than in MockVoiceService because the model layer has
    /// to recognise them in Release builds too, where the mock does not exist.
    static let placeholderVoicePrefix = "mock-voice-"

    static var isUsingMock: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: mockDefaultsKey)
        #else
        return false
        #endif
    }

    static var isConfigured: Bool {
        if isUsingMock { return true }
        return !elevenLabsKey.isEmpty
    }

    /// The only place that decides which implementation the app talks to.
    static func voiceService() -> VoiceService {
        #if DEBUG
        if isUsingMock { return MockVoiceService() }
        #endif
        return ElevenLabsClient()
    }

    /// Arabic-capable and stable on long-form.
    static let defaultModelId = "eleven_multilingual_v2"

    /// Half the price and much lower latency.
    static let fastModelId = "eleven_flash_v2_5"

    /// Hard ceiling per generation. The plan has no automatic overage, so the
    /// real risk is wasted credits, not a surprise bill.
    static let maxCharactersPerGeneration = 800

    static let requestTimeout: TimeInterval = 45
}
