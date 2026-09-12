import Foundation
import AuthenticationServices
import CryptoKit

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
        refreshToken = token.refresh_token
        accessToken = token.access_token ?? ""
        accessExpires = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600))
        email = Self.emailFrom(idToken: token.id_token)
        UserDefaults.standard.set(email, forKey: "jaddati.cloud.email")
        isSignedIn = !(refreshToken ?? "").isEmpty
    }

    func signOut() {
        refreshToken = nil
        accessToken = ""
        accessExpires = .distantPast
        email = ""
        UserDefaults.standard.removeObject(forKey: "jaddati.cloud.email")
        isSignedIn = false
    }

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.googleRedirectScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    // Someone closing the sheet is not a failure, and telling
                    // them it was would be the app arguing with them.
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: Failure.failed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
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
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(TokenReply.self, from: data) else {
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
            return accessToken
        } catch {
            // A refused refresh means access was taken away in the Google
            // account. Sign out rather than retry forever against a dead
            // token — and say so, so it can be given back deliberately.
            signOut()
            throw Failure.revoked
        }
    }

    // MARK: The backup

    struct BackedUp { let sent: Int; let skipped: Int }
    struct BroughtBack { let brought: Int; let failed: Int }

    private static func name(for personId: UUID) -> String {
        "person-\(personId.uuidString).jaddati.json"
    }

    /// One file per person, and the contents are exactly the archive the code
    /// handoff sends. Not a second format: a backup that cannot be read by the
    /// thing which restores archives is a backup nobody has ever tested.
    func backUp(library: Library) async throws -> BackedUp {
        working = true
        defer { working = false }

        let existing = try await listing()
        var sent = 0, skipped = 0

        for person in library.people {
            let exported = try Archive.export(person: person, library: library)
            defer { try? FileManager.default.removeItem(at: exported.url) }
            let body = try Data(contentsOf: exported.url)
            if body.count > 24 * 1024 * 1024 { skipped += 1; continue }

            try await upload(name: Self.name(for: person.id),
                             replacing: existing[Self.name(for: person.id)],
                             body: body)
            sent += 1
        }
        return BackedUp(sent: sent, skipped: skipped)
    }

    /// Everything up there, back. Each file goes through Archive.importArchive,
    /// so a restored person arrives by the identical path as one arriving from
    /// a code — same validation, same refusals, same fresh local ids.
    func restore(into library: Library) async throws -> BroughtBack {
        working = true
        defer { working = false }

        var brought = 0, failed = 0
        for (name, id) in try await listing() where name.hasPrefix("person-") {
            do {
                let data = try await download(id: id)
                let scratch = FileManager.default.temporaryDirectory
                    .appendingPathComponent("restore-\(UUID().uuidString).jaddati.json")
                try data.write(to: scratch, options: .atomic)
                defer { try? FileManager.default.removeItem(at: scratch) }
                _ = try Archive.importArchive(from: scratch, into: library)
                brought += 1
            } catch {
                failed += 1
            }
        }
        return BroughtBack(brought: brought, failed: failed)
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
        return Dictionary(uniqueKeysWithValues: (list.files ?? []).map { ($0.name, $0.id) })
    }

    private func download(id: String) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.driveFiles + "/\(id)?alt=media")!)
        request.setValue("Bearer \(try await freshAccessToken())", forHTTPHeaderField: "authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.driveRefused }
        return data
    }

    private func upload(name: String, replacing id: String?, body: Data) async throws {
        let boundary = "jaddati-\(UUID().uuidString)"
        var metadata: [String: Any] = ["name": name]
        if id == nil { metadata["parents"] = ["appDataFolder"] }

        var payload = Data()
        payload.append("--\(boundary)\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        payload.append(try JSONSerialization.data(withJSONObject: metadata))
        payload.append("\r\n--\(boundary)\r\ncontent-type: application/json\r\n\r\n".data(using: .utf8)!)
        payload.append(body)
        payload.append("\r\n--\(boundary)--".data(using: .utf8)!)

        let path = Self.driveUpload + (id.map { "/\($0)" } ?? "") + "?uploadType=multipart&fields=id"
        var request = URLRequest(url: URL(string: path)!)
        request.httpMethod = id == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(try await freshAccessToken())", forHTTPHeaderField: "authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        request.httpBody = payload

        let (_, response) = try await URLSession.shared.data(for: request)
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

    private static func randomURLSafe(_ bytes: Int) -> String {
        var raw = Data(count: bytes)
        _ = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(raw)
    }

    /// The address, read out of the id token without verifying it. Fine for a
    /// label — it came straight from Google's own token endpoint over TLS —
    /// and it is never used to decide anything.
    private static func emailFrom(idToken: String?) -> String {
        let parts = (idToken ?? "").split(separator: ".")
        guard parts.count > 1 else { return "" }
        var body = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 { body += "=" }
        guard let data = Data(base64Encoded: body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        return (json["email"] as? String) ?? ""
    }
}

extension CloudBackup: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
