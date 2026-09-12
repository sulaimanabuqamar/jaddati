import Foundation
import UIKit

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

    /// Where voice calls go.
    ///
    /// Unset, the app talks to ElevenLabs directly with a real key — which is
    /// what a local build should keep doing. Set to the proxy, the "key" above
    /// becomes the app token and the real key never leaves the server. See
    /// proxy/README.md for why a shared build must not carry the real one.
    static var voiceBaseURL: String {
        let value = (secrets["ELEVENLABS_BASE_URL"] as? String) ?? ""
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        return trimmed.isEmpty ? stockVoiceURL : trimmed
    }

    /// Which phone is spending, so the proxy can meter one device without the
    /// app having accounts. `identifierForVendor` is stable for this app on
    /// this device and disappears when the app is removed — a meter reading,
    /// not an identity. Nothing is stored next to it.
    static let deviceId: String =
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    /// True only when calls go somewhere we run. Against ElevenLabs and Groq
    /// directly the meter header means nothing to the recipient, so sending it
    /// would be handing an identifier to a third party for a purpose that does
    /// not exist there. Only the proxy is told which phone is asking.
    /// One flag per service, never a shared one. The proxy README describes
    /// relaying the questions while leaving voice on the stock host — with a
    /// single OR, that configuration sent the identifier straight to
    /// ElevenLabs, which is the exact thing this is here to prevent.
    static var sendsVoiceDeviceHeader: Bool { voiceBaseURL != stockVoiceURL }
    static var sendsTextDeviceHeader: Bool { llmBaseURL != stockTextURL }

    /// True if either does, for the one place that describes the app rather
    /// than making a request.
    static var sendsDeviceHeader: Bool { sendsVoiceDeviceHeader || sendsTextDeviceHeader }

    private static let stockVoiceURL = "https://api.elevenlabs.io"
    private static let stockTextURL = "https://api.groq.com/openai/v1"

    /// Our own relay. It is a post office, not a recipient: naming it in the
    /// disclosure would tell someone their recording goes to a workers.dev
    /// address and stops there, which is the opposite of what that screen
    /// exists to make plain. The data still reaches ElevenLabs and Groq, and
    /// the consent gate has to say so.
    static let relayURL = "https://jaddati-proxy.sulaimanabuqamar.workers.dev"
    private static var usesRelayVoice: Bool { voiceBaseURL == relayURL }
    private static var usesRelayText: Bool { llmBaseURL == relayURL }

    /// Named in the disclosure. Derived, because a build pointed at a relay is
    /// not talking to the company the screen would otherwise name.
    static var voiceProviderName: String {
        if isUsingMock { return "Offline test mode" }
        if voiceBaseURL == stockVoiceURL || usesRelayVoice { return "ElevenLabs" }
        return URL(string: voiceBaseURL)?.host ?? voiceBaseURL
    }

    static var textProviderName: String {
        if isUsingMock { return "Offline test mode" }
        if llmBaseURL == stockTextURL || usesRelayText { return "Groq" }
        return URL(string: llmBaseURL)?.host ?? llmBaseURL
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

    /// Whether the voice service can actually be called right now.
    ///
    /// Consent is part of this, not a separate check bolted on at each call
    /// site. Every screen in the app already asks this question before showing
    /// a control that would reach the network, so folding consent in here is
    /// what makes "keep everything on this phone" a real mode rather than a
    /// promise the interface forgets in one place.
    static var isConfigured: Bool {
        // Mock first, consent second. The offline test mode reaches no network
        // at all, so gating it behind a network-consent answer would let "keep
        // everything on this phone" switch off features that already do. The
        // real calls stay guarded at their own call sites regardless.
        if isUsingMock { return true }
        guard Consent.networkAllowed else { return false }
        return !elevenLabsKey.isEmpty
    }

    /// Which of the two reasons a network feature is unavailable. Saying "no
    /// key" to someone who simply declined is a lie, and saying "you declined"
    /// to someone on a keyless build sends them to the wrong screen.
    static var isOffByChoice: Bool { !isUsingMock && !Consent.networkAllowed }

    /// One sentence, true in either case, for the several screens that have to
    /// explain why a button is not there.
    static var unavailableMessage: String {
        isOffByChoice
            ? L("Everything is being kept on this phone, so this is switched off. You can change that under Privacy and data.")
            : L("This build has no voice service key, so no new audio can be created. Original recordings still play.")
    }

    static var unavailableTitle: String {
        isOffByChoice ? L("Kept on this phone") : L("Voice service not connected")
    }

    /// The only place that decides which implementation the app talks to.
    static func voiceService() -> VoiceService {
        #if DEBUG
        if isUsingMock { return MockVoiceService() }
        #endif
        return ElevenLabsClient()
    }

    /// Named in the consent card. A disclosure that says "a third-party voice
    /// service" without saying which one is not a disclosure.
    static var providerName: String { voiceProviderName }

    /// Arabic-capable and stable on long-form.
    static let defaultModelId = "eleven_multilingual_v2"

    /// Half the price and much lower latency.
    static let fastModelId = "eleven_flash_v2_5"

    /// Hard ceiling per generation. The plan has no automatic overage, so the
    /// real risk is wasted credits, not a surprise bill.
    static let maxCharactersPerGeneration = 2_500

    static let requestTimeout: TimeInterval = 120

    // MARK: Questions during a story

    /// Any OpenAI-compatible chat endpoint. Groq, OpenRouter, Together and a
    /// llama.cpp server on a laptop all speak this shape, so which open-weights
    /// model answers a child's question is a setting, not a rewrite.
    static var llmKey: String {
        if let env = ProcessInfo.processInfo.environment["LLM_API_KEY"], !env.isEmpty {
            return env
        }
        let value = (secrets["LLM_API_KEY"] as? String) ?? ""
        return value == "PASTE_YOUR_KEY_HERE" ? "" : value
    }

    static var llmBaseURL: String {
        let value = (secrets["LLM_BASE_URL"] as? String) ?? ""
        // Trimmed exactly like voiceBaseURL. Untrimmed, a trailing slash — a
        // spelling that works everywhere else, because each client trims at
        // use time — read as a different host and shipped the device id to
        // both stock providers.
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        return trimmed.isEmpty ? stockTextURL : trimmed
    }

    /// A string in Secrets.plist rather than a constant here, on purpose:
    /// hosted model ids get retired without notice, and swapping one should not
    /// need a code change five days before a demo. That is not hypothetical —
    /// the first id tried here, `llama-3.3-70b-versatile`, had already been
    /// retired by the time it was called. `spike/llm_spike.sh` prints the ids a
    /// given key can actually reach.
    ///
    /// Chosen by measurement on 10 Sep 2026 across three candidates: it held to
    /// one sentence when asked for one, answered in about a second, and reached
    /// for Gulf wording in Arabic unprompted. Fall back to `fallbackLLMModel`
    /// if the free tier throttles the larger model.
    static var llmModel: String {
        let value = (secrets["LLM_MODEL"] as? String) ?? ""
        return value.isEmpty ? "openai/gpt-oss-120b" : value
    }

    /// Second place in the same test: cleaner physics, but formal MSA rather
    /// than Gulf, and a smaller model. Swap it into Secrets.plist if needed.
    static let fallbackLLMModel = "qwen/qwen3.8-27b"

    static var isCompanionConfigured: Bool {
        // Mock first, consent second. The offline test mode reaches no network
        // at all, so gating it behind a network-consent answer would let "keep
        // everything on this phone" switch off features that already do. The
        // real calls stay guarded at their own call sites regardless.
        if isUsingMock { return true }
        guard Consent.networkAllowed else { return false }
        return !llmKey.isEmpty
    }

    static func storyCompanion() -> StoryCompanion {
        #if DEBUG
        if isUsingMock { return MockStoryCompanion() }
        #endif
        return LLMClient()
    }

    /// Speaking into the app rides the same host and the same key as the story
    /// questions. `-turbo`, not plain `large-v3`: the first version of this
    /// project measured turbo at 16.5% median CER on real Emirati dialect,
    /// while `large-v3` hallucinated "subscribe to the channel" onto near-silent
    /// audio at 86% CER.
    static var whisperModel: String {
        let value = (secrets["WHISPER_MODEL"] as? String) ?? ""
        return value.isEmpty ? "whisper-large-v3-turbo" : value
    }

    static var isTranscriptionConfigured: Bool {
        // Mock first, consent second. The offline test mode reaches no network
        // at all, so gating it behind a network-consent answer would let "keep
        // everything on this phone" switch off features that already do. The
        // real calls stay guarded at their own call sites regardless.
        if isUsingMock { return true }
        guard Consent.networkAllowed else { return false }
        return !llmKey.isEmpty
    }

    static func transcriber() -> Transcriber {
        #if DEBUG
        if isUsingMock { return MockTranscriber() }
        #endif
        return WhisperClient()
    }

    /// Shorter than the voice timeout. A child who has stopped the story is
    /// waiting in silence, and a slow answer is worse than a missing one.
    static let companionTimeout: TimeInterval = 20
}
