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
        Group {
            switch state {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
            case .downloaded:
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .padding(5)
        .glassEffect(.regular, in: .circle)
    }
}
