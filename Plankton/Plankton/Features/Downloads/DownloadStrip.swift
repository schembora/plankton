//
//  DownloadStrip.swift
//  Plankton
//
//  Every active transfer in one glass strip, with a storage meter beneath.
//  Replaces the stack of tall per-item progress rows, which pushed the
//  downloads grid below the fold as soon as a few things were in flight.
//

import SwiftUI

struct DownloadStrip: View {

    @Environment(DownloadService.self) private var downloads

    /// Home shows the transfers but not the running total — that belongs on
    /// the Downloads tab.
    var showsStorage = true

    private var active: [DownloadedMedia] { downloads.activeDownloads }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !active.isEmpty {
                transfers
            }
            if showsStorage {
                storageMeter
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - Transfers

    private var transfers: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloading \(active.count) \(active.count == 1 ? "item" : "items")")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let meta = metaText {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 0)
            }

            ProgressView(value: downloads.combinedProgress)
                .tint(.accentColor)

            VStack(spacing: 8) {
                ForEach(active) { media in
                    itemRow(media)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Combined rate and overall percentage, e.g. "6.1 MB/s · 42%".
    private var metaText: String? {
        var parts: [String] = []
        if let speed = downloads.combinedSpeedText {
            parts.append(speed)
        }
        parts.append("\(Int((downloads.combinedProgress * 100).rounded()))%")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func itemRow(_ media: DownloadedMedia) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 6, height: 6)

            Text(media.seriesName ?? media.title)
                .lineLimit(1)

            if let episodeLabel = media.episodeLabel {
                Text(episodeLabel)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(Int((progress(for: media) * 100).rounded()))%")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .contentShape(.rect)
        .contextMenu {
            Button("Cancel Download", systemImage: "xmark", role: .destructive) {
                downloads.cancelDownload(itemID: media.itemID)
            }
        }
    }

    private func progress(for media: DownloadedMedia) -> Double {
        guard case .downloading(let value)? = downloads.state(for: media.itemID) else { return 0 }
        return value
    }

    // MARK: - Storage

    /// Just what the downloads occupy. Comparing against device capacity was
    /// noise — the bar was invisible on any roomy device.
    @ViewBuilder
    private var storageMeter: some View {
        let used = downloads.totalDownloadedBytes
        if used > 0 {
            Text("\(DownloadService.sizeText(used)) downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
