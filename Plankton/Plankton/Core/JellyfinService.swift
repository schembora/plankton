//
//  JellyfinService.swift
//  Plankton
//
//  Owns the Jellyfin client, server connection, and user session.
//

import Foundation
import Get
import JellyfinAPI
import Network
import Observation
import UIKit

@Observable
final class JellyfinService {

    enum ConnectError: LocalizedError {
        case invalidAddress
        case noServerSelected

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "That doesn't look like a valid server address."
            case .noServerSelected: "No server has been selected."
            }
        }
    }

    // MARK: - Session state

    private(set) var client: JellyfinClient?
    private(set) var serverURL: URL?
    private(set) var serverName: String?
    private(set) var userID: String?
    private(set) var username: String?

    /// True when the server can't be reached but a cached session exists — the
    /// app stays open in offline mode and downloaded media remains playable.
    private(set) var isOffline = false

    /// The server chosen on the connect screen, before sign-in completes.
    private(set) var pendingServerURL: URL?
    private(set) var pendingServerName: String?

    var isSignedIn: Bool { client != nil && userID != nil }

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let accessToken = "accessToken"
        static let deviceID = "deviceID"
        static let serverURL = "serverURL"
        static let serverName = "serverName"
        static let userID = "userID"
        static let username = "username"
    }

    init() {
        // Restore the cached session synchronously: the app opens straight into
        // the library (or the downloads, when the server is unreachable) without
        // waiting on the network. The token is validated in the background.
        restoreCachedSession()
        startMonitoringConnectivity()

        if isSignedIn {
            Task { await validateSession() }
        }
    }

    // MARK: - Connect & sign in

    /// Validates that the given address points to a Jellyfin server. On success the server
    /// becomes the pending server for `signIn(username:password:)`.
    @discardableResult
    func validateServer(address: String) async throws -> PublicSystemInfo {
        guard let url = Self.normalizedURL(from: address) else {
            throw ConnectError.invalidAddress
        }

        let info = try await makeClient(url: url, requestTimeout: Self.connectTimeout)
            .send(Paths.getPublicSystemInfo).value
        pendingServerURL = url
        pendingServerName = info.serverName
        return info
    }

    func signIn(username: String, password: String) async throws {
        guard let serverURL = pendingServerURL else { throw ConnectError.noServerSelected }

        let client = makeClient(url: serverURL)
        let result = try await client.signIn(username: username, password: password)
        adoptSession(client: client, serverURL: serverURL, result: result)
    }

    /// Whether the pending server has Quick Connect turned on, so the sign-in
    /// screen only offers it when it can work. The endpoint returns a bare JSON
    /// bool, which the SDK surfaces as raw `Data`.
    func isQuickConnectEnabled() async -> Bool {
        guard let serverURL = pendingServerURL else { return false }

        let client = makeClient(url: serverURL, requestTimeout: Self.connectTimeout)
        guard let data = try? await client.send(Paths.getQuickConnectEnabled).value else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) == true
    }

    /// Runs the Quick Connect flow against the pending server: yields the
    /// user-facing code as soon as the server issues it, then polls until the
    /// code is approved from another signed-in Jellyfin session and completes
    /// sign-in. Cancelling the surrounding task stops the polling; the flow
    /// then returns without a session.
    func signInWithQuickConnect(onCode: (String) -> Void) async throws {
        guard let serverURL = pendingServerURL else { throw ConnectError.noServerSelected }

        let client = makeClient(url: serverURL)
        for try await event in client.quickConnect.connect() {
            switch event {
            case .polling(let code):
                onCode(code)
            case .authenticated(let secret):
                let result = try await client.signIn(quickConnectSecret: secret)
                adoptSession(client: client, serverURL: serverURL, result: result)
                return
            }
        }
    }

    /// Persists and adopts a freshly authenticated session, flipping `isSignedIn`.
    private func adoptSession(client: JellyfinClient, serverURL: URL, result: AuthenticationResult) {
        keychain.set(client.accessToken, forKey: Keys.accessToken)
        defaults.set(serverURL.absoluteString, forKey: Keys.serverURL)
        defaults.set(pendingServerName, forKey: Keys.serverName)
        defaults.set(result.user?.id, forKey: Keys.userID)
        defaults.set(result.user?.name, forKey: Keys.username)

        self.client = client
        self.serverURL = serverURL
        serverName = pendingServerName
        userID = result.user?.id
        username = result.user?.name
    }

    func signOut() async {
        let client = self.client

        // Clear local state first — signing out while offline shouldn't wait
        // on a server that can't be reached.
        keychain.set(nil, forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.serverURL)
        defaults.removeObject(forKey: Keys.serverName)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.username)

        self.client = nil
        serverURL = nil
        serverName = nil
        userID = nil
        username = nil
        isOffline = false
        pendingServerURL = nil
        pendingServerName = nil

        // Best-effort server-side session cleanup.
        if let client {
            try? await client.signOut()
        }
    }

    // MARK: - Requests & URLs

    func send<T: Decodable & Sendable>(_ request: Request<T>) async throws -> T {
        guard let client else { throw ConnectError.noServerSelected }
        return try await client.send(request).value
    }

    /// Requests that return no body, e.g. the playback reporting endpoints.
    func send(_ request: Request<Void>) async throws {
        guard let client else { throw ConnectError.noServerSelected }
        try await client.send(request)
    }

    /// Authenticated URL for an item image.
    func imageURL(itemID: String, type: ImageType, tag: String? = nil, maxWidth: Int? = nil) -> URL? {
        guard let client else { return nil }

        var parameters = Paths.GetItemImageParameters()
        parameters.tag = tag
        parameters.maxWidth = maxWidth
        parameters.quality = 90

        let request = Paths.getItemImage(itemID: itemID, imageType: type.rawValue, parameters: parameters)
        return client.url(with: request, queryAPIKey: true)
    }

    /// Resolves the best playable URL for an item by negotiating with the server via
    /// PlaybackInfo and an AVPlayer device profile. Returns a transcoded HLS URL for
    /// formats AVPlayer can't play natively (e.g. MKV), or a direct stream otherwise.
    func playbackURL(for item: BaseItemDto) async -> URL? {
        guard let client, let itemID = item.id, let userID else { return nil }

        var profile = DeviceProfile()
        profile.name = "Plankton AVPlayer"
        profile.maxStreamingBitrate = 20_000_000
        profile.directPlayProfiles = [
            DirectPlayProfile(audioCodec: "aac,ac3,eac3,mp3,alac", container: "mp4,m4v,mov", type: .video, videoCodec: "h264,hevc"),
        ]
        var hlsProfile = TranscodingProfile()
        hlsProfile.protocol = .hls
        hlsProfile.container = "fmp4"
        hlsProfile.type = .video
        hlsProfile.videoCodec = "h264"
        hlsProfile.audioCodec = "aac"
        hlsProfile.maxAudioChannels = "2"
        hlsProfile.enableSubtitlesInManifest = true
        profile.transcodingProfiles = [hlsProfile]
        profile.subtitleProfiles = [
            SubtitleProfile(format: "vtt", method: .hls),
        ]

        var body = PlaybackInfoDto()
        body.userID = userID
        body.deviceProfile = profile

        var parameters = Paths.GetPostedPlaybackInfoParameters()
        parameters.userID = userID

        guard let info = try? await send(Paths.getPostedPlaybackInfo(itemID: itemID, parameters: parameters, body)),
              let mediaSource = info.mediaSources?.first
        else { return nil }

        // Transcoded HLS — the URL already carries the play session and API key.
        if let transcodingURL = mediaSource.transcodingURL {
            var url = transcodingURL
            // Ask the server to list all subtitle tracks in the HLS manifest;
            // AVPlayer shows them in its native subtitle picker.
            if let subtitleIndex = Self.manifestSubtitleIndex(for: mediaSource) {
                url += "&SubtitleMethod=Hls&SubtitleStreamIndex=\(subtitleIndex)"
            }
            return client.url(path: url)
        }

        // Direct play of a natively supported file.
        if mediaSource.isSupportsDirectPlay == true, let container = mediaSource.container {
            var streamParameters = Paths.GetVideoStreamByContainerParameters()
            streamParameters.isStatic = true
            streamParameters.mediaSourceID = mediaSource.id ?? itemID
            streamParameters.deviceID = deviceID
            let request = Paths.getVideoStreamByContainer(itemID: itemID, container: container, parameters: streamParameters)
            return client.url(with: request, queryAPIKey: true)
        }

        return nil
    }

    // MARK: - Helpers

    /// Subtitle stream to mark as the manifest default: the server's default choice when
    /// there is one, otherwise -1 (all tracks listed, none enabled). Nil when the item
    /// has no subtitle streams at all.
    private static func manifestSubtitleIndex(for mediaSource: MediaSourceInfo) -> Int? {
        let subtitleStreams = (mediaSource.mediaStreams ?? []).filter { $0.type == .subtitle }
        guard !subtitleStreams.isEmpty else { return nil }

        if let defaultIndex = mediaSource.defaultSubtitleStreamIndex,
           subtitleStreams.contains(where: { $0.index == defaultIndex }) {
            return defaultIndex
        }
        return -1
    }

    /// True for connectivity failures (offline, server unreachable, timeouts) as
    /// opposed to server rejections such as an expired access token.
    nonisolated static func isNetworkError(_ error: Error) -> Bool {
        (error as NSError).domain == NSURLErrorDomain
    }

    /// True only when the server definitively rejected the access token (401/403).
    /// Anything else — unreachable host, timeout, 5xx from a proxy — is treated
    /// as a connectivity problem and keeps the session in offline mode.
    nonisolated static func isAuthFailure(_ error: Error) -> Bool {
        guard case APIError.unacceptableStatusCode(let statusCode) = error else { return false }
        return statusCode == 401 || statusCode == 403
    }

    /// Accepts anything from `192.168.1.5:8096` to `https://jellyfin.example.com` and
    /// returns a normalized URL. Bare hosts default to HTTP, as is typical for LAN servers.
    nonisolated static func normalizedURL(from address: String) -> URL? {
        var string = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        if !string.contains("://") {
            string = "http://" + string
        }
        while string.hasSuffix("/") {
            string.removeLast()
        }

        guard let url = URL(string: string), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Timeout for reachability checks. Validating the server — on launch or from
    /// the connect screen — should fail fast when it can't be reached and drop
    /// into offline mode, not hang on the system's minute-long defaults.
    private static let connectTimeout: TimeInterval = 3

    private var deviceID: String {
        if let existing = keychain.string(forKey: Keys.deviceID) {
            return existing
        }
        let new = UUID().uuidString
        keychain.set(new, forKey: Keys.deviceID)
        return new
    }

    private func makeClient(url: URL, accessToken: String? = nil, requestTimeout: TimeInterval? = nil) -> JellyfinClient {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let configuration = JellyfinClient.Configuration(
            url: url,
            accessToken: accessToken,
            client: "Plankton",
            deviceName: UIDevice.current.name,
            deviceID: deviceID,
            version: version
        )

        guard let requestTimeout else {
            return JellyfinClient(configuration: configuration)
        }

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = requestTimeout
        return JellyfinClient(configuration: configuration, sessionConfiguration: sessionConfiguration)
    }

    /// Restores the saved session from the Keychain and defaults without touching
    /// the network, so returning users never wait on a "Connecting…" screen.
    private func restoreCachedSession() {
        guard let urlString = defaults.string(forKey: Keys.serverURL),
              let url = URL(string: urlString),
              let token = keychain.string(forKey: Keys.accessToken)
        else { return }

        client = makeClient(url: url, accessToken: token)
        serverURL = url
        serverName = defaults.string(forKey: Keys.serverName)
        userID = defaults.string(forKey: Keys.userID)
        username = defaults.string(forKey: Keys.username)
    }

    /// Checks the saved token against the server. A rejection (e.g. expired token)
    /// signs the user out; a connectivity failure keeps the session and marks the
    /// app offline, leaving downloaded media available.
    private func validateSession() async {
        guard let url = serverURL, let token = keychain.string(forKey: Keys.accessToken) else { return }

        let validationClient = makeClient(url: url, accessToken: token, requestTimeout: Self.connectTimeout)

        do {
            let user = try await validationClient.send(Paths.getCurrentUser).value
            userID = user.id
            username = user.name
            defaults.set(user.id, forKey: Keys.userID)
            defaults.set(user.name, forKey: Keys.username)
            isOffline = false
        } catch {
            if Self.isAuthFailure(error) {
                // The token was rejected — back to the connect screen.
                await signOut()
            } else {
                // No connection, server down, server error — offline mode.
                isOffline = true
            }
        }
    }

    // MARK: - Offline mode

    /// Enters offline mode without a session — e.g. the connect screen couldn't
    /// reach a server. Downloads stay browsable since they live on the device.
    func enterOfflineMode() {
        isOffline = true
    }

    /// Leaves offline mode. With a session this signs out so the user can enter
    /// a new server address; without one it just returns to the connect screen.
    func leaveOfflineMode() async {
        if isSignedIn {
            await signOut()
        } else {
            isOffline = false
        }
    }

    // MARK: - Connectivity

    private let pathMonitor = NWPathMonitor()

    /// Revalidates the session when connectivity returns while offline, so
    /// browsing resumes without relaunching the app.
    private func startMonitoringConnectivity() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { await self?.revalidateIfOffline() }
        }
        pathMonitor.start(queue: .main)
    }

    /// User-initiated retry from the offline header. Unlike the automatic
    /// path this runs even without connectivity having returned, so tapping
    /// Retry always does something.
    func retryConnection() async {
        guard isSignedIn else { return }
        await validateSession()
    }

    private func revalidateIfOffline() async {
        // Only a real session can revalidate; session-less offline mode (from
        // the connect screen) is left to the user to back out of.
        guard isOffline, isSignedIn else { return }
        await validateSession()
    }
}
