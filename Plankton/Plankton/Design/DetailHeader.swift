//
//  DetailHeader.swift
//  Plankton
//
//  The poster-beside-text block every detail page leads with.
//

import SwiftUI

/// Artwork with the title, details, and description set beside it.
///
/// Shared so a movie, a series, and an episode read as the same screen — the
/// poster is a slot rather than a parameter because an episode's is a link to
/// its series, while a movie's is just artwork.
struct DetailHeader<Poster: View, Lead: View>: View {

    let title: String
    let metadata: String?
    let overview: String?

    /// The source file's resolution, codec and bitrate. Kept off the main
    /// details line and set smaller: it's reference information, not something
    /// anyone scans a page for.
    var mediaSummary: String?

    /// The community score, on its own line under the details.
    var rating: String?

    /// Where the rating leads when tapped. Without one it's plain text — an
    /// item the server has no IMDb ID for still has a score worth showing.
    var ratingURL: URL?

    /// Holds the collapsed description at its full height. For a page that
    /// swaps between items in place, so the content below doesn't jump.
    var reservesDescriptionSpace = false

    @ViewBuilder let poster: Poster

    /// Optional line above the title — a breadcrumb back to a parent.
    @ViewBuilder let lead: Lead

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            poster

            VStack(alignment: .leading, spacing: 6) {
                lead

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                // One string rather than a row of them: beside a poster there
                // isn't width for four details, and text wraps where an HStack
                // would push the last of them off the edge.
                if let metadata {
                    Text(metadata)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let mediaSummary {
                    Text(mediaSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let rating {
                    ratingLabel(rating)
                }

                // Set beside the poster rather than under the whole header.
                // Four lines of this column run to about the poster's height,
                // so the block stays square before the description spills past.
                if let overview, !overview.isEmpty {
                    ExpandableText(text: overview, reservesSpace: reservesDescriptionSpace)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The score as a link where there's somewhere to send it. Tinted rather
    /// than badged: it sits inline with the details above it, and a button's
    /// worth of chrome around one number overwhelmed that whole column.
    @ViewBuilder
    private func ratingLabel(_ rating: String) -> some View {
        let label = Label(rating, systemImage: "star.fill")
            .font(.subheadline)
            .fontWeight(.medium)

        if let ratingURL {
            Link(destination: ratingURL) { label }
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Rated \(rating) out of 10. View on IMDb")
        } else {
            label.foregroundStyle(.secondary)
        }
    }
}

extension DetailHeader where Lead == EmptyView {

    init(
        title: String,
        metadata: String?,
        overview: String?,
        mediaSummary: String? = nil,
        rating: String? = nil,
        ratingURL: URL? = nil,
        reservesDescriptionSpace: Bool = false,
        @ViewBuilder poster: () -> Poster
    ) {
        self.init(
            title: title,
            metadata: metadata,
            overview: overview,
            mediaSummary: mediaSummary,
            rating: rating,
            ratingURL: ratingURL,
            reservesDescriptionSpace: reservesDescriptionSpace,
            poster: poster,
            lead: { EmptyView() }
        )
    }
}

/// The poster itself, at the size and trim both detail pages use.
struct DetailPoster: View {

    let artwork: Artwork?
    var width: CGFloat = 100

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        MediaImage(artwork: artwork)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }
}
