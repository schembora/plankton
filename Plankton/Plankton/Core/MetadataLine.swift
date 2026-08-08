//
//  MetadataLine.swift
//  Plankton
//
//  The one place the app's metadata separator lives.
//

import Foundation

extension Sequence where Element == String? {

    /// The present parts joined the way every subtitle in the app joins them —
    /// "S2 E4 · 45m · 1999".
    ///
    /// Nil rather than an empty string when nothing is present, so a caller can
    /// leave the line out instead of drawing a blank one.
    var metadataLine: String? {
        let parts = compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
