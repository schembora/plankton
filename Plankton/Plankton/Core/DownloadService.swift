//
//  DownloadService.swift
//  Plankton
//
//  Downloads media for offline playback and tracks what's on device.
//

import AVFoundation
import Foundation
import JellyfinAPI
import Observation

/// A media item saved on device, or on its way there.
struct DownloadedMedia: Codable, Equatable, Identifiable {

    enum Status: String, Codable {
        case downloading
        case downloaded
    }

    let itemID: String
    let title: String
    let seriesName: String?
    let seriesID: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let runtimeTicks: Int?
    let isMovie: Bool
    let startedAt: Date

    var status: Status

    /// Bookmark to the downloaded asset, resolved on each use since the
    /// system may move it between launches. Nil until the download completes.
    var fileBookmark: Data?
    var fileSize: Int64?

    var id: String { itemID }

    /// e.g. "S2 E4" for episodes.
    var episodeLabel: String? {
        guard !isMovie else { return nil }
        var parts: [String] = []
        if let seasonNumber { parts.append("S\(seasonNumber)") }
        if let episodeNumber { parts.append("E\(episodeNumber)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Groups a series' episodes together in the downloads grid.
    var seriesGroupID: String? {
        guard !isMovie else { return nil }
        return seriesID ?? seriesName ?? title
    }

    /// e.g. "1h 32m" or "45m".
    var runtimeText: String? {
        guard let runtimeTicks else { return nil }
        let minutes = runtimeTicks / 600_000_000
        guard minutes > 0 else { return nil }

        if minutes >= 60 {
            let remainder = minutes % 60
            return remainder > 0 ? "\(minutes / 60)h \(remainder)m" : "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }
}

@Observable
final class DownloadService: NSObject {

    /// Where a download stands, for buttons and badges.
    enum State: Equatable {
        case downloading(progress: Double)
        case downloaded
        case failed
    }

    /// All known downloads, newest first in the UI; persisted to disk.
    private(set) var media: [DownloadedMedia] = []

    /// Live progress (0...1) for active downloads, keyed by item ID.
    private(set) var progress: [String: Double] = [:]

    /// Smoothed transfer rate in bytes/sec for active downloads, keyed by item ID.
    private(set) var speeds: [String: Double] = [:]

    /// Item IDs whose most recent attempt failed, until retried or relaunched.
    private var failures: Set<String> = []

    private var activeTasks: [String: AVAssetDownloadTask] = [:]

    /// Last (bytes received, timestamp) sample per item, used to derive `speeds`.
    private var byteSamples: [String: (bytes: Int64, date: Date)] = [:]

    /// Created in `init` (the delegate is `self`); never changes afterwards.
    @ObservationIgnored private var session: AVAssetDownloadURLSession!

    private let jellyfin: JellyfinService
    private let directory: URL

    /// Set by the app delegate when the system relaunches the app to deliver
    /// background download events; handed back in `urlSessionDidFinishEvents`.
    static var backgroundCompletionHandler: (() -> Void)?

    init(jellyfin: JellyfinService, directory: URL? = nil) {
        self.jellyfin = jellyfin
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Downloads", directoryHint: .isDirectory)
        super.init()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.schembor.Plankton.downloads"
        )
        session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )

        try? FileManager.default.createDirectory(at: postersDirectory, withIntermediateDirectories: true)
        media = Self.loadRecords(from: recordsURL)
        reconcileWithSystem()
    }

    // MARK: - State

    func state(for itemID: String?) -> State? {
        guard let itemID else { return nil }
        if failures.contains(itemID) { return .failed }
        guard let record = media.first(where: { $0.itemID == itemID }) else { return nil }

        switch record.status {
        case .downloaded: return .downloaded
        case .downloading: return .downloading(progress: progress[itemID] ?? 0)
        }
    }

    func hasFailed(_ itemID: String) -> Bool {
        failures.contains(itemID)
    }

    /// Human-readable transfer rate for an active download, e.g. "4.2 MB/s".
    /// Nil until enough samples have arrived to estimate a rate, or once the
    /// download isn't actively transferring.
    func speedText(for itemID: String?) -> String? {
        guard let itemID, let bytesPerSecond = speeds[itemID], bytesPerSecond >= 1 else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
        return "\(formatted)/s"
    }

    // MARK: - Downloading

    /// Starts downloading an item for offline playback, negotiating the same
    /// HLS stream the player would use so any format becomes playable offline.
    func download(item: BaseItemDto) async {
        guard let itemID = item.id, !itemID.isEmpty else { return }
        guard state(for: itemID) != .downloaded, activeTasks[itemID] == nil else { return }

        upsertRecord(for: item)
        failures.remove(itemID)

        guard let url = await jellyfin.playbackURL(for: item) else {
            failures.insert(itemID)
            return
        }

        // Snapshot artwork so the Downloads tab looks right offline. The
        // poster is the item's own primary image (episodes fall back to the
        // series poster), and the backdrop is the wide banner image (episodes
        // fall back to the series backdrop).
        var artwork: Data?
        if let source = item.primaryImageSource,
           let posterURL = jellyfin.imageURL(itemID: source.itemID, type: .primary, tag: source.tag, maxWidth: 400),
           let (data, _) = try? await URLSession.shared.data(from: posterURL) {
            artwork = data
            try? data.write(to: posterFileURL(forItemID: itemID), options: .atomic)
        }

        if let source = item.backdropImageSource,
           let backdropURL = jellyfin.imageURL(itemID: source.itemID, type: .backdrop, tag: source.tag, maxWidth: 1200),
           let (data, _) = try? await URLSession.shared.data(from: backdropURL) {
            try? data.write(to: backdropFileURL(forItemID: itemID), options: .atomic)

            // When the backdrop is the series' (the usual fallback), share it
            // across the series so its page works no matter which episode was
            // downloaded first.
            if item.seriesID == source.itemID,
               !FileManager.default.fileExists(atPath: seriesBackdropFileURL(forSeriesID: source.itemID).path) {
                try? data.write(to: seriesBackdropFileURL(forSeriesID: source.itemID), options: .atomic)
            }
        }

        // The series' own cover art, fetched once, so the series tile and page
        // show the real series poster instead of an episode still.
        if item.type == .episode,
           let seriesID = item.seriesID,
           let seriesTag = item.seriesPrimaryImageTag,
           !FileManager.default.fileExists(atPath: seriesPosterFileURL(forSeriesID: seriesID).path),
           let seriesURL = jellyfin.imageURL(itemID: seriesID, type: .primary, tag: seriesTag, maxWidth: 400),
           let (data, _) = try? await URLSession.shared.data(from: seriesURL) {
            try? data.write(to: seriesPosterFileURL(forSeriesID: seriesID), options: .atomic)
        }

        let asset = AVURLAsset(url: url)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: item.name ?? itemID,
            assetArtworkData: artwork,
            options: nil
        ) else {
            failures.insert(itemID)
            return
        }

        task.taskDescription = itemID
        activeTasks[itemID] = task
        progress[itemID] = 0
        task.resume()
    }

    /// Retries a failed download by re-fetching the item from the server.
    func retry(itemID: String) async {
        guard let userID = jellyfin.userID,
              let item = try? await jellyfin.send(Paths.getItem(itemID: itemID, userID: userID))
        else { return }

        await download(item: item)
    }

    /// Cancels an in-progress download and removes its partial data.
    func cancelDownload(itemID: String) {
        activeTasks[itemID]?.cancel()
        // The delegate's cancelled callback purges; do it now too so the
        // UI updates even if the callback is delayed.
        purge(itemID: itemID)
    }

    /// Removes a download (or cancels an in-progress one) and its files.
    func delete(itemID: String) {
        let seriesID = media.first(where: { $0.itemID == itemID })?.seriesID
        activeTasks[itemID]?.cancel()
        activeTasks[itemID] = nil

        if let url = localURL(forItemID: itemID) {
            try? FileManager.default.removeItem(at: url)
        }

        media.removeAll { $0.itemID == itemID }
        progress[itemID] = nil
        clearSpeedTracking(itemID: itemID)
        failures.remove(itemID)
        removeArtwork(itemID: itemID)

        // The series' art belongs to every episode; drop it only when the last
        // one goes.
        if let seriesID, !media.contains(where: { $0.seriesID == seriesID }) {
            try? FileManager.default.removeItem(at: seriesPosterFileURL(forSeriesID: seriesID))
            try? FileManager.default.removeItem(at: seriesBackdropFileURL(forSeriesID: seriesID))
        }

        saveRecords()
    }

    /// Removes every download. Called on sign out.
    func deleteAll() {
        for itemID in media.map(\.itemID) {
            delete(itemID: itemID)
        }
    }

    // MARK: - Files

    /// Local URL of a completed download, resolving (and refreshing) its bookmark.
    func localURL(forItemID itemID: String) -> URL? {
        guard let index = media.firstIndex(where: { $0.itemID == itemID }),
              media[index].status == .downloaded,
              let bookmark = media[index].fileBookmark
        else { return nil }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            return nil
        }

        if isStale, let fresh = try? url.bookmarkData() {
            media[index].fileBookmark = fresh
            saveRecords()
        }
        return url
    }

    /// Local file URL of the poster snapshot saved alongside a download.
    func posterFileURL(forItemID itemID: String) -> URL {
        postersDirectory.appending(path: "\(itemID).jpg")
    }

    /// Local file URL of the wide backdrop snapshot, used for the series banner.
    func backdropFileURL(forItemID itemID: String) -> URL {
        postersDirectory.appending(path: "\(itemID)-backdrop.jpg")
    }

    /// Local file URL of the series' own poster, shared by all its episodes.
    func seriesPosterFileURL(forSeriesID seriesID: String) -> URL {
        postersDirectory.appending(path: "\(seriesID)-series.jpg")
    }

    /// Local file URL of the series' own backdrop, shared by all its episodes.
    func seriesBackdropFileURL(forSeriesID seriesID: String) -> URL {
        postersDirectory.appending(path: "\(seriesID)-series-backdrop.jpg")
    }

    // MARK: - Persistence

    private var recordsURL: URL {
        directory.appending(path: "metadata.json")
    }

    private var postersDirectory: URL {
        directory.appending(path: "posters", directoryHint: .isDirectory)
    }

    private func upsertRecord(for item: BaseItemDto) {
        guard let itemID = item.id else { return }

        if let index = media.firstIndex(where: { $0.itemID == itemID }) {
            media[index].status = .downloading
        } else {
            media.append(DownloadedMedia(
                itemID: itemID,
                title: item.name ?? String(localized: "Unknown"),
                seriesName: item.seriesName,
                seriesID: item.seriesID,
                seasonNumber: item.parentIndexNumber,
                episodeNumber: item.indexNumber,
                runtimeTicks: item.runTimeTicks,
                isMovie: item.type == .movie,
                startedAt: Date(),
                status: .downloading
            ))
        }
        saveRecords()
    }

    /// Drops an in-progress record and its artwork, e.g. after cancellation.
    private func purge(itemID: String) {
        activeTasks[itemID] = nil
        progress[itemID] = nil
        clearSpeedTracking(itemID: itemID)
        failures.remove(itemID)
        media.removeAll { $0.itemID == itemID && $0.status == .downloading }
        removeArtwork(itemID: itemID)
        saveRecords()
    }

    private func clearSpeedTracking(itemID: String) {
        speeds[itemID] = nil
        byteSamples[itemID] = nil
    }

    private func removeArtwork(itemID: String) {
        try? FileManager.default.removeItem(at: posterFileURL(forItemID: itemID))
        try? FileManager.default.removeItem(at: backdropFileURL(forItemID: itemID))
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(media) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }

    private static func loadRecords(from url: URL) -> [DownloadedMedia] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DownloadedMedia].self, from: data)) ?? []
    }

    // MARK: - Session

    /// Reattaches downloads that outlived the last launch: the system keeps
    /// background asset downloads alive, so any record still marked
    /// `downloading` without a matching live task is dropped, along with
    /// poster files nothing references anymore.
    private func reconcileWithSystem() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }

            var activeIDs: Set<String> = []
            for case let task as AVAssetDownloadTask in tasks {
                guard let itemID = task.taskDescription else { continue }
                activeIDs.insert(itemID)
                activeTasks[itemID] = task
            }

            let before = media.count
            media.removeAll { $0.status == .downloading && !activeIDs.contains($0.itemID) }
            if media.count != before { saveRecords() }

            removeOrphanedPosters()
        }
    }

    private func removeOrphanedPosters() {
        var valid: Set<String> = []
        for media in media {
            valid.insert("\(media.itemID).jpg")
            valid.insert("\(media.itemID)-backdrop.jpg")
            if let seriesID = media.seriesID {
                valid.insert("\(seriesID)-series.jpg")
                valid.insert("\(seriesID)-series-backdrop.jpg")
            }
        }

        let files = (try? FileManager.default.contentsOfDirectory(atPath: postersDirectory.path)) ?? []
        for file in files where !valid.contains(file) {
            try? FileManager.default.removeItem(at: postersDirectory.appending(path: file))
        }
    }
}

// MARK: - AVAssetDownloadDelegate

extension DownloadService: AVAssetDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let itemID = assetDownloadTask.taskDescription else { return }
        updateSpeed(itemID: itemID, bytesReceived: assetDownloadTask.countOfBytesReceived)

        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected > 0 else { return }

        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        progress[itemID] = min(max(loaded / expected, 0), 1)
    }

    /// Derives a smoothed bytes/sec rate from successive byte-count samples.
    /// AVAssetDownloadTask reports progress via loaded time ranges, not bytes,
    /// so speed is tracked separately from `progress` using the task's own
    /// (inherited from URLSessionTask) byte counters. Samples are throttled to
    /// half-second windows and blended with an exponential moving average so
    /// the displayed rate doesn't jitter between consecutive callbacks.
    private func updateSpeed(itemID: String, bytesReceived: Int64) {
        let now = Date()
        guard let previous = byteSamples[itemID] else {
            byteSamples[itemID] = (bytesReceived, now)
            return
        }

        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed >= 0.5, bytesReceived >= previous.bytes else { return }
        byteSamples[itemID] = (bytesReceived, now)

        let instantaneous = Double(bytesReceived - previous.bytes) / elapsed
        speeds[itemID] = speeds[itemID].map { $0 * 0.7 + instantaneous * 0.3 } ?? instantaneous
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let itemID = assetDownloadTask.taskDescription,
              let index = media.firstIndex(where: { $0.itemID == itemID })
        else { return }

        media[index].status = .downloaded
        media[index].fileBookmark = try? location.bookmarkData()
        media[index].fileSize = try? FileManager.default.allocatedSizeOfDirectory(at: location)
        progress[itemID] = nil
        clearSpeedTracking(itemID: itemID)
        saveRecords()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let itemID = task.taskDescription else { return }
        activeTasks[itemID] = nil
        progress[itemID] = nil
        clearSpeedTracking(itemID: itemID)

        guard let error else { return } // Success is handled in didFinishDownloadingTo.

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            purge(itemID: itemID)
        } else {
            failures.insert(itemID)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DownloadService.backgroundCompletionHandler?()
        DownloadService.backgroundCompletionHandler = nil
    }
}

private extension FileManager {

    /// Total allocated size of a directory (or single file) in bytes.
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
