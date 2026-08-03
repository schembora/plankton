//
//  ResumeCard.swift
//  Plankton
//
//  Wide 16:9 card for Continue Watching — the still or backdrop rather than a
//  poster, with how far in you are, how much is left, and whether the file is
//  already on the device.
//

import JellyfinAPI
import SwiftUI

struct ResumeCard: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads

    let item: BaseItemDto

    private var isSaved: Bool {
        downloads.state(for: item.id) == .downloaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let meta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 232)
    }

    /// "S2 E4 · 18m left", falling back to whichever half is known.
    private var meta: String? {
        let parts = [item.episodeLabel, item.remainingText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { JellyfinImage(url: wideURL, placeholderIcon: "tv") }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular, in: .circle)
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                if isSaved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .glassEffect(.regular, in: .circle)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = item.watchedProgress {
                    WatchedProgressBar(progress: progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }

    private var wideURL: URL? {
        guard let source = item.wideImageSource else { return nil }
        let type: ImageType = item.type == .episode ? .primary : .backdrop
        return jellyfin.imageURL(itemID: source.itemID, type: type, tag: source.tag, maxWidth: 700)
    }
}
