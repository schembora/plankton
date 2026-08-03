//
//  OfflineHeader.swift
//  Plankton
//
//  States the offline situation at the top of the Downloads tab, rather than
//  floating a capsule over whatever you were looking at.
//

import SwiftUI

struct OfflineHeader: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline — showing downloads")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Can't reach \(jellyfin.serverName ?? "your server")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    isRetrying = true
                    Task {
                        await jellyfin.retryConnection()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Text("Retry")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.glass)
                .disabled(isRetrying)
            }

            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    /// e.g. "12 items · 18.4 GB · all playable now".
    private var summary: String? {
        let playable = downloads.media.filter { $0.status == .downloaded }
        guard !playable.isEmpty else { return nil }

        let size = playable.reduce(Int64(0)) { $0 + ($1.fileSize ?? 0) }
        var parts = ["\(playable.count) \(playable.count == 1 ? "item" : "items")"]
        if size > 0 {
            parts.append(DownloadService.sizeText(size))
        }
        parts.append("all playable now")
        return parts.joined(separator: " · ")
    }
}
