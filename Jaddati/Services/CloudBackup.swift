import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Signing in with Google, and keeping a copy of your own people in your own
/// Drive so a lost phone is not a lost voice.
///
/// It is NOT how you give someone to the family. Your sister's Drive is a
/// different account and cannot see yours — the code on the Setup screen is
/// for that. The two get confused constantly, so the screen says which is
/// which and this comment says it again for whoever reads the code next.
///
/// The folder is Drive's appDataFolder: private to this app, invisible in the
/// person's own Drive, and no access to a single file they did not put there
/// through us. Asking for anything wider to store our own backup would be
/// helping ourselves to their documents.
///
/// No SDK. ASWebAuthenticationSession is a system framework and — the part
/// that makes this possible here — it intercepts the callback itself, so the
/// redirect scheme needs no URL type in Info.plist. This project generates
/// its Info.plist and cannot declare one.
@MainActor
final class CloudBackup: NSObject, ObservableObject {
    static let shared = CloudBackup()

    @Published private(set) var email: String = ""
    @Published private(set) var isSignedIn = false
    @Published private(set) var working = false

    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "jaddati.cloud.refresh") }
        set { UserDefaults.standard.set(newValue, forKey: "jaddati.cloud.refresh") }
    }
    private var accessToken = ""
    private var accessExpires = Date.distantPast
    /// Not persisted on purpose. It lasts an hour, and a cold start gets a
    /// fresh one from the refresh token in the same round trip it was going to
    /// make anyway — so writing an hour-old identity to disk buys nothing and
    /// leaves one more thing lying about that names the person.
    private var idToken = ""
    private var session: ASWebAuthenticationSession?

    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let driveFiles = "https://www.googleapis.com/drive/v3/files"
    private static let driveUpload = "https://www.googleapis.com/upload/drive/v3/files"
    private static let scopes = "openid email https://www.googleapis.com/auth/drive.appdata"

    override init() {
        super.init()
        isSignedIn = !(refreshToken ?? "").isEmpty
        email = UserDefaults.standard.string(forKey: "jaddati.cloud.email") ?? ""
    }

    enum Failure: LocalizedError {
        case notConfigured, cancelled, failed, revoked, driveRefused

        var errorDescription: String? {
            switch self {
            case .notConfigured: return L("Signing in is not set up on this build.")
            case .cancelled:     return nil
            case .failed:        return L("That sign-in could not be completed. Try again.")
            case .revoked:       return L("Google access has ended. Sign in again.")
            case .driveRefused:  return L("Google Drive refused that. Try again.")
            }
        }
    }

    // MARK: Signing in

    func signIn() async throws {
        guard AppConfig.googleConfigured else { throw Failure.notConfigured }

        let verifier = Self.randomURLSafe(32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(16)

        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            .init(name: "client_id", value: AppConfig.googleClientId),
            .init(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]

        let callback = try await present(components.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // The state has to come back untouched, or this is not the answer to
        // the question we asked.
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw Failure.failed
        }

        // No client secret: an iOS client does not have one, which is the
        // whole reason PKCE is here.
        let form = [
            "client_id": AppConfig.googleClientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": AppConfig.googleRedirectURI,
        ]
        let token = try await postForm(form)
        // Google sends a refresh token on the first consent and may send none
        // afterwards. Assigning it unconditionally overwrote a good one with
        // nil, and the next launch found itself signed out with no way back
        // except consenting again.
        if let issued = token.refresh_token, !issued.isEmpty {
            refreshToken = issued
        }
        accessToken = token.access_token ?? ""
        accessExpires = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600))
        idToken = token.id_token ?? ""
        email = Self.emailFrom(idToken: token.id_token)
        UserDefaults.standard.set(email, forKey: "jaddati.cloud.email")
        isSignedIn = !(refreshToken ?? "").isEmpty
    }

    func signOut() {
        refreshToken = nil
        accessToken = ""
        accessExpires = .distantPast
        idToken = ""
        email = ""
        UserDefaults.standard.removeObject(forKey: "jaddati.cloud.email")
        isSignedIn = false
    }

    /// Who is signed in, in a form the relay can check for itself — or nil.
    ///
    /// Not the access token. That one opens this person's Drive, and the relay
    /// has no business holding a key to it; the id token says which account is
    /// asking and authorises nothing at all, which is the exact amount of power
    /// this needs to carry.
    ///
    /// Nil rather than a throw when nobody is signed in: the caller's next move
    /// is to ask them to, not to report a failure.
    func accountToken() async -> String? {
        guard !(refreshToken ?? "").isEmpty else { return nil }
        if Self.lifeLeft(idToken) > 60 { return idToken }
        // Deliberately not freshAccessToken()'s own answer: the two expire on
        // separate clocks, and an access token with half an hour left on it
        // says nothing whatever about the id token beside it. Asking for the
        // access token is only the way to make the round trip happen; what is
        // wanted is what that trip leaves in idToken.
        guard (try? await freshAccessToken()) != nil else { return nil }
        return Self.lifeLeft(idToken) > 0 ? idToken : nil
    }

    /// Seconds this id token has left. Zero for anything unreadable, which is
    /// the safe answer: it means "ask Google for another" rather than "send
    /// this and hope". The relay checks the signature properly at its end.
    private static func lifeLeft(_ idToken: String) -> TimeInterval {
        guard let exp = claims(idToken)["exp"] as? Double else { return 0 }
        return max(0, exp - Date().timeIntervalSince1970)
    }

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // TWO paths can reach this continuation: the session's completion
            // handler, and the check on start() below. On a failed start both
            // of them fired, the continuation resumed twice, and Swift traps on
            // that — the app did not report an error, it died.
            //
            // Apple documents start() == false as "did not begin" with no
            // callback. That is not what happens. So the continuation is
            // one-shot and whichever path arrives first wins. Everything here
            // runs on the main thread, so the flag needs no lock.
            var settled = false
            func finish(_ result: Result<URL, Error>) {
                guard !settled else { return }
                settled = true
                continuation.resume(with: result)
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.googleRedirectScheme
            ) { callback, error in
                if let callback {
                    finish(.success(callback))
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    // Someone closing the sheet is not a failure, and telling
                    // them it was would be the app arguing with them.
                    finish(.failure(Failure.cancelled))
                } else {
                    finish(.failure(Failure.failed))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            // Returns false when there is nothing to present from. Unchecked,
            // the caller waits for a sheet that never opened, forever, with the
            // spinner turning.
            if !session.start() {
                finish(.failure(Failure.failed))
            }
        }
    }

    // MARK: Tokens

    private struct TokenReply: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Int?
        let id_token: String?
    }

    private func postForm(_ fields: [String: String]) async throws -> TokenReply {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = fields
            .map { "\($0.key)=\(Self.escape($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let reply = try? JSONDecoder().decode(TokenReply.self, from: data) else {
            // Only one answer means the grant itself is dead. Everything else —
            // a 500, a 429, a captive portal — is the call failing, and must
            // not be read as Google having taken access away.
            let said = String(data: data, encoding: .utf8) ?? ""
            if said.contains("invalid_grant") { throw Failure.revoked }
            throw Failure.failed
        }
        return reply
    }

    private func freshAccessToken() async throws -> String {
        if !accessToken.isEmpty, Date() < accessExpires.addingTimeInterval(-60) {
            return accessToken
        }
        guard let refresh = refreshToken, !refresh.isEmpty else { throw Failure.revoked }
        do {
            let token = try await postForm([
                "client_id": AppConfig.googleClientId,
                "refresh_token": refresh,
                "grant_type": "refresh_token",
            ])
            accessToken = token.access_token ?? ""
            accessExpires = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600))
            // Google sends a new id token with every refresh of a grant that
            // asked for openid. Keeping the old one when it does not is right
            // for the address label and wrong for the relay, which is why
            // accountToken checks the life left on what it gets back rather
            // than assuming this line gave it something fresh.
            if let issued = token.id_token, !issued.isEmpty { idToken = issued }
            return accessToken
        } catch Failure.revoked {
            // Google said invalid_grant: access really was taken away in the
            // account. Sign out rather than retry forever against a dead token.
            signOut()
            throw Failure.revoked
        } catch {
            // Anything else is the network, not the grant. Signing out here
            // threw away a working connection because a request timed out once
            // — and the only way back was the whole consent screen again.
            throw Failure.failed
        }
    }

    // MARK: The backup

    struct BackedUp { let sent: Int; let skipped: Int; let atRisk: Int }
    struct BroughtBack { let brought: Int; let failed: Int; let already: Int }

    /// The file name carries the key, which is how a second device recognises
    /// someone it already has. Takes the key rather than the local id: those
    /// are the same string only until the first restore.
    private static func name(for key: String) -> String {
        "person-\(key).jaddati.json"
    }

    private static func key(inFileNamed name: String) -> String {
        name.dropFirst("person-".count)
            .replacingOccurrences(of: ".jaddati.json", with: "")
    }

    /// One file per person, and the contents are exactly the archive the code
    /// handoff sends. Not a second format: a backup that cannot be read by the
    /// thing which restores archives is a backup nobody has ever tested.
    func backUp(library: Library) async throws -> BackedUp {
        working = true
        defer { working = false }

        let existing = try await listing()
        var sent = 0, skipped = 0, atRisk = 0

        for person in library.people {
            // Gather here, build off the main actor — the same split the code
            // handoff uses, and for the same reason: this reads and base64s
            // every recording the person has, and doing that on the main actor
            // is a frozen screen for the whole backup.
            //
            // `includingKeptClips` is the whole difference between this and
            // sharing. A backup that brings back her recordings but not the
            // things the family chose to keep is not an answer to "the phone
            // is gone".
            // Where her file lives in Drive. Set once, on the first backup,
            // and carried from then on — so backing up after a restore writes
            // over the same file instead of standing a second one beside it.
            let key = person.cloudKey ?? person.id.uuidString
            if person.cloudKey == nil {
                var stamped = person
                stamped.cloudKey = key
                library.update(stamped)
            }

            let outline = Archive.plan(person: person, library: library,
                                       includingKeptClips: true)
            let built = try await Task.detached(priority: .userInitiated) {
                () throws -> Archive.ExportResult in
                try Archive.build(outline)
            }.value
            // Deleted here rather than inside the task: the file IS what gets
            // uploaded now, not a step on the way to some bytes. In a loop
            // `defer` runs at the end of each pass, so nothing accumulates.
            defer { try? FileManager.default.removeItem(at: built.url) }

            // Refuse to replace a good backup with a worse one. If recordings
            // could not be read off this phone, the copy in Drive is more
            // complete than the copy we are about to upload, and overwriting it
            // turns a recoverable problem into a permanent loss. Fewer than
            // expected is enough — it does not have to be all of them.
            //
            // Originals only. A kept clip left behind is a smaller loss than a
            // recording left behind, and counting the two together would let
            // someone with many clips and one unreadable recording block their
            // own backup for good.
            if built.carriedOriginals < outline.originals.count { atRisk += 1; continue }

            var size = 0
            if let values = try? built.url.resourceValues(forKeys: [.fileSizeKey]),
               let bytes = values.fileSize {
                size = bytes
            }
            if size > 24 * 1024 * 1024 { skipped += 1; continue }

            try await upload(name: Self.name(for: key),
                             replacing: existing[Self.name(for: key)],
                             file: built.url)
            sent += 1
        }
        return BackedUp(sent: sent, skipped: skipped, atRisk: atRisk)
    }

    /// Everything up there, back. Each file goes through Archive.importArchive,
    /// so a restored person arrives by the identical path as one arriving from
    /// a code — same validation, same refusals, same fresh local ids.
    func restore(into library: Library) async throws -> BroughtBack {
        working = true
        defer { working = false }

        var brought = 0, failed = 0, already = 0
        for (name, id) in try await listing() where name.hasPrefix("person-") {
            // Someone already here under this key is the same person, and
            // importing her again put a second copy on the People tab — every
            // single time the button was pressed. Compared without case,
            // because the phone writes an uppercase UUID and the browser a
            // lowercase one for what is otherwise the same value.
            let key = Self.key(inFileNamed: name)
            if library.people.contains(where: {
                ($0.cloudKey ?? $0.id.uuidString).caseInsensitiveCompare(key) == .orderedSame
            }) { already += 1; continue }
            do {
                let data = try await download(id: id)
                let scratch = FileManager.default.temporaryDirectory
                    .appendingPathComponent("restore-\(UUID().uuidString).jaddati.json")
                try data.write(to: scratch, options: .atomic)
                defer { try? FileManager.default.removeItem(at: scratch) }
                let arrived = try Archive.importArchive(from: scratch, into: library)
                // Remember where she came from, or the next backup writes a
                // second file for the person just restored.
                var stamped = arrived.person
                stamped.cloudKey = key
                library.update(stamped)
                brought += 1
            } catch {
                failed += 1
            }
        }
        return BroughtBack(brought: brought, failed: failed, already: already)
    }

    private struct FileList: Decodable {
        struct Entry: Decodable { let id: String; let name: String }
        let files: [Entry]?
    }

    private func listing() async throws -> [String: String] {
        var request = URLRequest(url: URL(string:
            Self.driveFiles + "?spaces=appDataFolder&fields=files(id,name)&pageSize=200")!)
        request.setValue("Bearer \(try await freshAccessToken())", forHTTPHeaderField: "authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(FileList.self, from: data) else {
            throw Failure.driveRefused
        }
        // appDataFolder tolerates two files with one name, and a backup that
        // ran twice creates exactly that. `uniqueKeysWithValues` traps on the
        // duplicate — a crash, in the middle of the thing meant to keep the
        // recordings safe. Keep the last, which is the newer of the two.
        return Dictionary((list.files ?? []).map { ($0.name, $0.id) },
                          uniquingKeysWith: { _, newer in newer })
    }

    private func download(id: String) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.driveFiles + "/\(id)?alt=media")!)
        request.setValue("Bearer \(try await freshAccessToken())", forHTTPHeaderField: "authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.driveRefused }
        return data
    }

    /// Sends the archive from a file rather than from bytes.
    ///
    /// This used to take the archive as `Data`, and by the time Drive saw it
    /// the same audio existed four times over: the base64 strings inside the
    /// archive, the JSON they were encoded into, that same file read straight
    /// back off disk, and the multipart body built by appending around it —
    /// which reallocates as it grows, so briefly a fifth time. Backing up a
    /// family was hundreds of megabytes resident and iOS killed the app for
    /// it, which is not an error the app can report: the process is gone.
    ///
    /// Now the envelope is assembled on disk and URLSession streams it. Peak
    /// memory is one 512 KB chunk.
    private func upload(name: String, replacing id: String?, file: URL) async throws {
        let boundary = "jaddati-\(UUID().uuidString)"
        var metadata: [String: Any] = ["name": name]
        if id == nil { metadata["parents"] = ["appDataFolder"] }

        let envelope = FileManager.default.temporaryDirectory
            .appendingPathComponent("jaddati-upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: envelope) }

        var prologue = Data()
        prologue.append("--\(boundary)\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        prologue.append(try JSONSerialization.data(withJSONObject: metadata))
        prologue.append("\r\n--\(boundary)\r\ncontent-type: application/json\r\n\r\n".data(using: .utf8)!)
        try prologue.write(to: envelope, options: .atomic)

        // Scoped, so both handles are closed before the upload reads the file.
        // A `defer` at function level would close them after it.
        do {
            let sink = try FileHandle(forWritingTo: envelope)
            defer { try? sink.close() }
            _ = try sink.seekToEnd()

            let source = try FileHandle(forReadingFrom: file)
            defer { try? source.close() }
            while let chunk = try source.read(upToCount: 512 * 1024), !chunk.isEmpty {
                try sink.write(contentsOf: chunk)
            }
            try sink.write(contentsOf: "\r\n--\(boundary)--".data(using: .utf8)!)
        }

        let path = Self.driveUpload + (id.map { "/\($0)" } ?? "") + "?uploadType=multipart&fields=id"
        var request = URLRequest(url: URL(string: path)!)
        request.httpMethod = id == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(try await freshAccessToken())", forHTTPHeaderField: "authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "content-type")

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: envelope)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.driveRefused }
    }

    // MARK: Small things

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A PKCE verifier made of zeros would be a verifier an attacker can
    /// guess, so the failure path matters more than the happy one: if the
    /// Security framework declines, fall back to the system generator rather
    /// than returning whatever was already in the buffer.
    private static func randomURLSafe(_ bytes: Int) -> String {
        var raw = Data(count: bytes)
        let status = raw.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, bytes, base)
        }
        if status != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            raw = Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &rng) })
        }
        return base64URL(raw)
    }

    /// The address, read out of the id token without verifying it. Fine for a
    /// label — it came straight from Google's own token endpoint over TLS —
    /// and it is never used to decide anything.
    private static func emailFrom(idToken: String?) -> String {
        claims(idToken ?? "")["email"] as? String ?? ""
    }

    /// The claims inside an id token, read without verifying the signature.
    private static func claims(_ idToken: String) -> [String: Any] {
        let parts = idToken.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        var body = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 { body += "=" }
        guard let data = Data(base64Encoded: body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }
}

extension CloudBackup: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            // A fresh ASPresentationAnchor() is an empty window belonging to no
            // scene, so handing one back guarantees start() fails rather than
            // presenting anything — which is exactly what happened. Look
            // harder before giving up: the key window of a foreground scene,
            // then any window of one, then any window at all.
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let active = scenes.filter { $0.activationState == .foregroundActive }
            let windows = (active.isEmpty ? scenes : active).flatMap(\.windows)
            return windows.first { $0.isKeyWindow }
                ?? windows.first
                ?? ASPresentationAnchor()
        }
    }
}
