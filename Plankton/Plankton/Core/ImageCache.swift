//
//  ImageCache.swift
//  Plankton
//
//  Two-layer artwork cache: decoded images in memory, bytes on disk.
//

import CryptoKit
import Foundation
import Observation
import UIKit

/// Loads artwork once and keeps it.
///
/// `AsyncImage` — what this replaces — holds no decoded-image cache, so every
/// poster scrolling back into view was re-decoded even when its bytes were
/// still around. The memory layer here stores decoded `UIImage`s so a revisit
/// costs nothing, and the disk layer means a relaunch doesn't re-download the
/// library. Entries are addressed by `Artwork.cacheKey`, never by URL.
///
/// `@Observable` only so this can be injected with `.environment(_:)` like the
/// other services; there is no observable state to watch.
@MainActor
@Observable
final class ImageCache {

    private let jellyfin: JellyfinService
    private let memory = NSCache<NSString, UIImage>()
    private let disk = DiskStore()

    /// One load per key. A grid can ask for the same series poster from several
    /// cells at once, and a cell that scrolls out and back asks again before the
    /// first request lands — all of them should await the one request.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(jellyfin: JellyfinService) {
        self.jellyfin = jellyfin
        memory.totalCostLimit = 64 * 1024 * 1024
        Task { await disk.trim() }
    }

    /// Memory hit, if there is one. Synchronous so a view can draw a cached
    /// image on its first frame instead of flashing its placeholder.
    func cached(_ artwork: Artwork) -> UIImage? {
        memory.object(forKey: artwork.cacheKey as NSString)
    }

    func image(for artwork: Artwork) async -> UIImage? {
        if let hit = cached(artwork) { return hit }

        let key = artwork.cacheKey
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [disk] in
            await load(artwork, key: key, disk: disk)
        }
        inFlight[key] = task

        let image = await task.value
        inFlight[key] = nil

        if let image {
            memory.setObject(image, forKey: key as NSString, cost: image.cacheCost)
        }
        return image
    }

    /// Drops everything. Called on sign-out so one account's artwork isn't left
    /// on the device for the next.
    func clear() {
        memory.removeAllObjects()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        Task { await disk.removeAll() }
    }

    // MARK: - Loading

    private func load(_ artwork: Artwork, key: String, disk: DiskStore) async -> UIImage? {
        switch artwork {
        case let .local(url, fallback):
            if let image = await Self.decodeFile(at: url) { return image }
            guard let fallback else { return nil }
            return await Self.decodeFile(at: fallback)

        case .remote:
            if artwork.isDiskCacheable, let data = await disk.data(forKey: key) {
                return await Self.decode(data)
            }
            guard let url = remoteURL(for: artwork),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let image = await Self.decode(data)
            else { return nil }

            if artwork.isDiskCacheable {
                await disk.store(data, forKey: key)
            }
            return image
        }
    }

    private func remoteURL(for artwork: Artwork) -> URL? {
        guard case let .remote(itemID, type, tag, maxWidth) = artwork else { return nil }
        return jellyfin.imageURL(itemID: itemID, type: type, tag: tag, maxWidth: maxWidth)
    }

    /// Decoding is the expensive half, so it happens off the main actor and
    /// eagerly — `preparingForDisplay` does the work now rather than leaving it
    /// for the render server mid-scroll.
    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }

    private nonisolated static func decodeFile(at url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }.value
    }
}

// MARK: - Disk

/// The on-disk half, in `Caches/` so the system may reclaim it under storage
/// pressure — none of it is anything the app can't fetch again.
private actor DiskStore {

    private let directory: URL
    private let sizeLimit = 256 * 1024 * 1024

    init() {
        directory = URL.cachesDirectory.appending(path: "Artwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(forKey key: String) -> Data? {
        try? Data(contentsOf: fileURL(forKey: key))
    }

    func store(_ data: Data, forKey key: String) {
        try? data.write(to: fileURL(forKey: key), options: .atomic)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Evicts oldest-first when the cache outgrows its budget. iOS purges
    /// `Caches/` on its own, but only under real storage pressure — this keeps
    /// the footprint sane in the meantime.
    func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, size: Int, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate
            else { return nil }
            return (url, size, modified)
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > sizeLimit else { return }

        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= sizeLimit { return }
        }
    }

    /// Keys carry server-supplied image tags, so they're hashed rather than
    /// trusted as filenames.
    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        return directory.appending(path: digest.map { String(format: "%02x", $0) }.joined())
    }
}

private extension UIImage {

    /// Rough decoded size in bytes, so `NSCache` evicts by real memory use
    /// rather than treating a thumbnail and a backdrop as equal.
    var cacheCost: Int {
        guard let cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
