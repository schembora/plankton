//
//  LiveTVGuide.swift
//  Plankton
//
//  The guide: the grid, and a readout of whatever was tapped in it.
//

import JellyfinAPI
import SwiftUI

/// Wraps the grid with the one thing it can't say for itself.
///
/// The grid is UIKit — see `GuideGrid` for why — and everything around it stays
/// SwiftUI. The split is deliberate: layout is the part that needed UIKit, and
/// nothing else here does.
struct LiveTVGuide: View {

    let channels: [BaseItemDto]

    /// Programmes keyed by the channel they're on.
    let listings: [String: [BaseItemDto]]

    var startingChannelID: String?
    let onRefresh: () async -> Void

    /// Last, so it reads as the trailing closure at the call site.
    let onSelect: (BaseItemDto) -> Void

    @State private var now = Date()
    @State private var selection: GuideSelection?

    private struct GuideSelection {
        let channel: BaseItemDto
        let programme: BaseItemDto
    }

    /// The grid starts at the half hour on or before now, so the columns line
    /// up with the times people expect rather than with the moment they looked.
    private var start: Date {
        let floored = (now.timeIntervalSinceReferenceDate / GuideMetrics.slot).rounded(.down) * GuideMetrics.slot
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    var body: some View {
        GuideGrid(
            model: GuideModel(
                channels: channels,
                listings: listings,
                start: start,
                now: now,
                selectedProgrammeID: selection?.programme.id,
                startingChannelID: startingChannelID
            ),
            onRefresh: onRefresh,
            onSelectProgramme: { channel, programme in
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Tapping the same block again puts the bar away: a
                    // selection you can't undo is a mode you're stuck in.
                    selection = programme.id == selection?.programme.id
                        ? nil
                        : GuideSelection(channel: channel, programme: programme)
                }
            },
            onSelectChannel: onSelect
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if let selection {
                selectionBar(selection)
            }
        }
        .background(.black.opacity(0.15))
        // The "on air" shading is only right for a moment.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    /// Says what was tapped, and offers the one thing that can be done about
    /// it. A programme in the future can't be played, but its channel can.
    private func selectionBar(_ selection: GuideSelection) -> some View {
        HStack(spacing: 12) {
            // Only where the guide actually carries one: many listings have no
            // artwork, and an empty frame beside every title reads as broken.
            if let artwork = selection.programme.artwork(.primary, maxWidth: 300) {
                MediaImage(artwork: artwork, placeholderIcon: "tv")
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.programme.name ?? "Programme")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // The channel is already named in the column that was tapped
                // to get here; what it can't tell you is what the thing is.
                Text([
                    selection.programme.airingStartText,
                    selection.programme.airingEndText,
                ].metadataLine ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let overview = selection.programme.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button {
                onSelect(selection.channel)
            } label: {
                Label(
                    selection.programme.isAiringNow ? "Watch" : "Watch Live",
                    systemImage: "play.fill"
                )
                .font(.subheadline)
            }
            .buttonStyle(.glassProminent)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.selection = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selection")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
