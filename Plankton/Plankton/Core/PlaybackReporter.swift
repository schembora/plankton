//
//  PlaybackReporter.swift
//  Plankton
//
//  Reports playback to the server so watch position is shared with every
//  other Jellyfin client — this is what keeps Continue Watching honest.
//

import Foundation
import JellyfinAPI

/// Jellyfin measures time in 100-nanosecond ticks.
private let ticksPerSecond = 10_000_000.0

@MainActor
final class PlaybackReporter {

    /// How often progress is posted while playing. Jellyfin only needs a
    /// periodic heartbeat; the stop report is what pins the final position.
    static let progressInterval: TimeInterval = 30

    private let jellyfin: JellyfinService
    private let itemID: String

    /// Guards against a stop report racing in after the view is torn down twice.
    private var hasStopped = false

    init(jellyfin: JellyfinService, itemID: String) {
        self.jellyfin = jellyfin
        self.itemID = itemID
    }

    static func ticks(fromSeconds seconds: Double) -> Int {
        Int(seconds * ticksPerSecond)
    }

    static func seconds(fromTicks ticks: Int) -> Double {
        Double(ticks) / ticksPerSecond
    }

    func started(atSeconds seconds: Double) async {
        var info = PlaybackStateInfo()
        info.itemID = itemID
        info.positionTicks = Self.ticks(fromSeconds: seconds)
        info.canSeek = true
        info.isPaused = false

        try? await jellyfin.send(Paths.reportPlaybackStart(info))
    }

    func progress(atSeconds seconds: Double, isPaused: Bool) async {
        guard !hasStopped else { return }

        var info = PlaybackStateInfo()
        info.itemID = itemID
        info.positionTicks = Self.ticks(fromSeconds: seconds)
        info.canSeek = true
        info.isPaused = isPaused

        try? await jellyfin.send(Paths.reportPlaybackProgress(info))
    }

    func stopped(atSeconds seconds: Double) async {
        guard !hasStopped else { return }
        hasStopped = true

        var info = PlaybackStopInfo()
        info.itemID = itemID
        info.positionTicks = Self.ticks(fromSeconds: seconds)

        try? await jellyfin.send(Paths.reportPlaybackStopped(info))
    }
}
