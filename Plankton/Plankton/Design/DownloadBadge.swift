//
//  DownloadBadge.swift
//  Plankton
//
//  Small glass indicator showing an item is downloaded or on its way.
//

import SwiftUI

struct DownloadBadge: View {

    let state: DownloadService.State

    var body: some View {
        switch state {
        case .downloading(let progress):
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
        case .downloaded:
            Image(systemName: "checkmark")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(5)
                .glassEffect(.regular, in: .circle)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(5)
                .glassEffect(.regular, in: .circle)
        }
    }
}
