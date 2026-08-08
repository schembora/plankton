//
//  GlassRow.swift
//  Plankton
//
//  The app's tappable glass row, with its trailing chevron.
//

import SwiftUI

/// A row of glass with a chevron at its trailing edge — what every "this opens
/// something else" control on a detail page is built from.
struct GlassRow<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
