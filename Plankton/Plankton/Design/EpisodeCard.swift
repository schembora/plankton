//
//  EpisodeCard.swift
//  Plankton
//
//  The shared episode row — 16:9 thumbnail, S2 E4 label, title, runtime —
//  used by the series detail page and the downloads series page.
//

import SwiftUI

struct EpisodeCard<Thumb: View, Accessory: View>: View {

    let label: String?
    let title: String
    let runtimeText: String?
    let watchedProgress: Double?
    let thumb: Thumb
    let accessory: Accessory

    init(
        label: String?,
        title: String,
        runtimeText: String?,
        watchedProgress: Double? = nil,
        @ViewBuilder thumb: () -> Thumb,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self.title = title
        self.runtimeText = runtimeText
        self.watchedProgress = watchedProgress
        self.thumb = thumb()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            thumb
                .frame(width: 140, height: 80)
                .overlay(alignment: .bottom) {
                    if let watchedProgress {
                        WatchedProgressBar(progress: watchedProgress)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if let runtimeText {
                    Text(runtimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
