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
        return trimmed.isEmpty ? "https://api.elevenlabs.io" : trimmed
    }

    /// Which phone is spending, so the proxy can meter one device without the
    /// app having accounts. `identifierForVendor` is stable for this app on
    /// this device and disappears when the app is removed — a meter reading,
    /// not an identity. Nothing is stored next to it.
    static let deviceId: String =
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

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

    /// Named in the consent card. A disclosure that says "a third-party voice
    /// service" without saying which one is not a disclosure.
    static var providerName: String { isUsingMock ? "Offline test mode" : "ElevenLabs" }

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
        return value.isEmpty ? "https://api.groq.com/openai/v1" : value
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
        if isUsingMock { return true }
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
        if isUsingMock { return true }
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
