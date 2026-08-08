//
//  ExpandableText.swift
//  Plankton
//
//  Long body copy clamped to a few lines, with a control to read the rest.
//

import SwiftUI

/// Body text collapsed to `lineLimit` lines, expanding in place when tapped.
///
/// The toggle appears only when the text really is longer than the clamp — a
/// two-line synopsis shouldn't grow a "More" button that does nothing.
struct ExpandableText: View {

    let text: String
    var lineLimit: Int = 4

    /// Holds the collapsed block at its full line count even when the text is
    /// shorter. Worth it where one of these is swapped for another in place —
    /// otherwise each description sets its own height and everything below
    /// jumps as they change.
    var reservesSpace = false

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            clampedText
                .background { truncationProbe }

            if isTruncated {
                Button(isExpanded ? "Less" : "More") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
            }
        }
        // A detail page fills its overview in after the full item loads, and
        // the state above outlives that swap: without a reset, the previous
        // item's answer decides whether this one gets a button.
        .onChange(of: text) { _, _ in
            isTruncated = false
            isExpanded = false
        }
    }

    @ViewBuilder
    private var clampedText: some View {
        if isExpanded {
            Text(text)
        } else {
            Text(text).lineLimit(lineLimit, reservesSpace: reservesSpace)
        }
    }

    /// Lays the whole text into the space the clamped copy occupies. When it
    /// doesn't fit, `ViewThatFits` falls through to the second branch — which
    /// is the only signal SwiftUI offers that a `Text` is being truncated.
    ///
    /// Keyed on the text so a new overview re-runs the measurement rather than
    /// reusing the branch already on screen.
    private var truncationProbe: some View {
        ViewThatFits(in: .vertical) {
            Text(text).hidden()
            Color.clear.onAppear { isTruncated = true }
        }
        .id(text)
    }
}
