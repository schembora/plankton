//
//  JellyfinService.swift
//  Plankton
//
//  Owns the Jellyfin client, server connection, and user session.
//

import Foundation
import Get
import JellyfinAPI
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
    private(set) var isRestoringSession = true

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
    }

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Connect & sign in

    /// Validates that the given address points to a Jellyfin server. On success the server
    /// becomes the pending server for `signIn(username:password:)`.
    @discardableResult
    func validateServer(address: String) async throws -> PublicSystemInfo {
        guard let url = Self.normalizedURL(from: address) else {
            throw ConnectError.invalidAddress
        }

        let info = try await makeClient(url: url).send(Paths.getPublicSystemInfo).value
        pendingServerURL = url
        pendingServerName = info.serverName
        return info
    }

    func signIn(username: String, password: String) async throws {
        guard let serverURL = pendingServerURL else { throw ConnectError.noServerSelected }

        let client = makeClient(url: serverURL)
        let result = try await client.signIn(username: username, password: password)

        keychain.set(client.accessToken, forKey: Keys.accessToken)
        defaults.set(serverURL.absoluteString, forKey: Keys.serverURL)
        defaults.set(pendingServerName, forKey: Keys.serverName)

        self.client = client
        self.serverURL = serverURL
        self.serverName = pendingServerName
        userID = result.user?.id
        self.username = result.user?.name
    }

    func signOut() async {
        if let client {
            try? await client.signOut()
        }

        keychain.set(nil, forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.serverURL)
        defaults.removeObject(forKey: Keys.serverName)

        client = nil
        serverURL = nil
        serverName = nil
        userID = nil
        username = nil
        pendingServerURL = nil
        pendingServerName = nil
    }

    // MARK: - Requests & URLs

    func send<T: Decodable & Sendable>(_ request: Request<T>) async throws -> T {
        guard let client else { throw ConnectError.noServerSelected }
        return try await client.send(request).value
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
        hlsProfile.container = "ts"
        hlsProfile.type = .video
        hlsProfile.videoCodec = "h264"
        hlsProfile.audioCodec = "aac"
        hlsProfile.maxAudioChannels = "2"
        profile.transcodingProfiles = [hlsProfile]

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
            return client.url(path: transcodingURL)
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

    private var deviceID: String {
        if let existing = keychain.string(forKey: Keys.deviceID) {
            return existing
        }
        let new = UUID().uuidString
        keychain.set(new, forKey: Keys.deviceID)
        return new
    }

    private func makeClient(url: URL, accessToken: String? = nil) -> JellyfinClient {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let configuration = JellyfinClient.Configuration(
            url: url,
            accessToken: accessToken,
            client: "Plankton",
            deviceName: UIDevice.current.name,
            deviceID: deviceID,
            version: version
        )
        return JellyfinClient(configuration: configuration)
    }

    private func restoreSession() async {
        defer { isRestoringSession = false }

        guard let urlString = defaults.string(forKey: Keys.serverURL),
              let url = URL(string: urlString),
              let token = keychain.string(forKey: Keys.accessToken)
        else { return }

        let client = makeClient(url: url, accessToken: token)

        do {
            let user = try await client.send(Paths.getCurrentUser).value
            self.client = client
            serverURL = url
            serverName = defaults.string(forKey: Keys.serverName)
            userID = user.id
            username = user.name
        } catch {
            keychain.set(nil, forKey: Keys.accessToken)
        }
    }
}
