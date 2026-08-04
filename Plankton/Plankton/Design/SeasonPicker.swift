//
//  SeasonPicker.swift
//  Plankton
//
//  The shared season selector — a scrolling row of chips.
//

import SwiftUI

/// Picks which season's episodes to show.
///
/// Chips rather than a menu, so switching seasons is one tap instead of two,
/// and shared between the series detail page and a downloaded series for the
/// same reason `PosterTile` is shared: the two screens show the same thing and
/// should not look like different apps.
///
/// Generic over the season because the two callers hold different types — the
/// server page has `BaseItemDto` seasons, a downloaded series has only the
/// season numbers its episodes carry.
struct SeasonPicker<Season, ID: Hashable>: View {

    let seasons: [Season]
    @Binding var selection: ID?
    let id: (Season) -> ID
    let label: (Season) -> String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(seasons.enumerated()), id: \.offset) { _, season in
                    chip(for: season)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(for season: Season) -> some View {
        let isSelected = id(season) == selection

        return Button {
            selection = id(season)
        } label: {
            Text(label(season))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
                    } else {
                        Capsule().strokeBorder(.tertiary, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
