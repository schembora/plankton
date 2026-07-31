//
//  PosterTile.swift
//  Plankton
//
//  The shared 2:3 poster tile — rounded artwork, title, subtitle, and an
//  optional download badge. Used by PosterCard (server artwork) and
//  DownloadCard (on-device artwork) so every grid and shelf looks the same.
//

import SwiftUI

struct PosterTile<Poster: View>: View {

    let title: String
    let subtitle: String?
    let badge: DownloadService.State?
    let poster: Poster

    init(
        title: String,
        subtitle: String? = nil,
        badge: DownloadService.State? = nil,
        @ViewBuilder poster: () -> Poster
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.poster = poster()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { poster }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        DownloadBadge(state: badge)
                            .padding(6)
                    }
                }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
