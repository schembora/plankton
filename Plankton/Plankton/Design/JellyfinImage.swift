//
//  JellyfinImage.swift
//  Plankton
//
//  Async image loaded from a Jellyfin server with a subtle placeholder.
//

import SwiftUI

struct JellyfinImage: View {

    let url: URL?
    var placeholderIcon: String = "film"

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder(icon: "photo")
            default:
                placeholder(icon: placeholderIcon)
            }
        }
    }

    private func placeholder(icon: String) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }
}
