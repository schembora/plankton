//
//  DownloadProgressRow.swift
//  Plankton
//
//  A detailed row for one in-progress download: poster, title, a linear
//  progress bar, percent complete, and live transfer speed.
//

import SwiftUI

struct DownloadProgressRow: View {

    @Environment(DownloadService.self) private var downloads

    let media: DownloadedMedia

    private var progress: Double {
        guard case .downloading(let value)? = downloads.state(for: media.itemID) else { return 0 }
        return value
    }

    var body: some View {
        HStack(spacing: 12) {
            LocalPosterImage(url: downloads.posterFileURL(forItemID: media.itemID))
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(media.seriesName ?? media.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let episodeLabel = media.episodeLabel {
                    Text("\(episodeLabel) · \(media.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: progress)

                HStack(spacing: 4) {
                    Text("\(Int((progress * 100).rounded()))%")
                    if let speedText = downloads.speedText(for: media.itemID) {
                        Text("·")
                        Text(speedText)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .contextMenu {
            Button("Cancel Download", systemImage: "xmark", role: .destructive) {
                downloads.cancelDownload(itemID: media.itemID)
            }
        }
    }
}
