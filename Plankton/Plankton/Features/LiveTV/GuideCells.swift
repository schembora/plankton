//
//  GuideCells.swift
//  Plankton
//
//  What the guide's grid draws in each of its slots.
//

import JellyfinAPI
import SwiftUI

/// One programme, as wide as it is long.
struct GuideProgrammeCell: View {

    let programme: BaseItemDto
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(programme.name ?? "")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)

            if let startText = programme.airingStartText {
                Text(startText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(programme.isAiringNow ? 0.18 : 0.08))
        }
        // The outline is what identifies a block too narrow to hold a word, so
        // it has to read at a couple of points wide.
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .padding(.trailing, 2)
    }
}

/// The channel, pinned at the left edge of its own row.
struct GuideChannelCell: View {

    let channel: BaseItemDto
    var isStarting = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // A fixed box for every logo. Fitting to height alone lets a
                // wide mark run several times the width of a square one, and
                // the column reads as ragged.
                MediaImage(artwork: channel.artwork(.primary, maxWidth: 160), contentMode: .fit)
                    .frame(width: 40, height: 26)

                Text(channel.channelNumber ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                if isStarting {
                    ProgressView().scaleEffect(0.7).padding(.trailing, 4)
                }
            }
            .overlay(alignment: .trailing) { edge(.vertical) }
            .overlay(alignment: .bottom) { edge(.horizontal) }
        }
        .buttonStyle(.plain)
    }

    private func edge(_ axis: Axis) -> some View {
        Rectangle()
            .fill(.white.opacity(0.28))
            .frame(
                width: axis == .vertical ? 0.5 : nil,
                height: axis == .horizontal ? 0.5 : nil
            )
    }
}

/// The clock along the top.
struct GuideTimeAxis: View {

    let start: Date

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<GuideMetrics.slotCount, id: \.self) { index in
                let time = start.addingTimeInterval(Double(index) * GuideMetrics.slot)

                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: GuideMetrics.slot / 60 * GuideMetrics.minuteWidth, alignment: .leading)
                    .padding(.leading, 6)
                    // The same divisions as the grid below, so a label reads
                    // as belonging to the column under it.
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(index.isMultiple(of: 2) ? 0.22 : 0.1))
                            .frame(width: 0.5)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(height: 0.5)
        }
    }
}

/// Where the column and the clock meet. Blank on purpose: a time label here
/// would belong to a column the channel cells are covering.
struct GuideCorner: View {

    var body: some View {
        Rectangle()
            .fill(.clear)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.white.opacity(0.28)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.28)).frame(height: 0.5)
            }
    }
}
