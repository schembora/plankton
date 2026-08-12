//
//  AcknowledgementsView.swift
//  Plankton
//
//  The open source components Plankton ships, and their licences.
//

import SwiftUI

/// One component Plankton links against.
private struct Acknowledgement: Identifiable {

    let name: String

    /// Nil where the project declares no licence, rather than guessing at one.
    var license: String?

    let url: URL

    var id: String { name }
}

/// What Plankton is built on.
///
/// Not only courtesy: mpv and FFmpeg are LGPL, which requires the app to say it
/// uses them, name the licence, and point at the source the binaries came from.
struct AcknowledgementsView: View {

    private let playback: [Acknowledgement] = [
        .init(name: "mpv", license: "LGPL-3.0", url: URL(string: "https://mpv.io")!),
        .init(name: "FFmpeg", license: "LGPL-3.0", url: URL(string: "https://ffmpeg.org")!),
        .init(name: "MPVKit", license: "LGPL-3.0", url: URL(string: "https://github.com/mpvkit/MPVKit")!),
    ]

    /// Where the LGPL source actually is. Named separately from mpv and
    /// MPVKit because it is the build Plankton ships, not either of those.
    private let source: [Acknowledgement] = [
        .init(name: "Plankton, including mpvkit/", license: "Apache-2.0", url: URL(string: "https://github.com/schembora/plankton")!),
    ]

    private let server: [Acknowledgement] = [
        .init(name: "Jellyfin SDK", url: URL(string: "https://github.com/jellyfin/jellyfin-sdk-swift")!),
    ]

    private let networking: [Acknowledgement] = [
        .init(name: "Get", license: "MIT", url: URL(string: "https://github.com/kean/Get")!),
        .init(name: "SwiftNIO", license: "Apache-2.0", url: URL(string: "https://github.com/apple/swift-nio")!),
    ]

    var body: some View {
        List {
            Section {
                rows(playback)
            } header: {
                Text("Playback")
            } footer: {
                // The LGPL notice proper. Naming the build matters as much as
                // naming the project: what ships is a patched mpv, so this has
                // to point at where that build comes from rather than at mpv,
                // and the link has to keep working.
                Text("mpv and FFmpeg are used under the LGPL v3.0, without the optional GPL components. Plankton links a patched build of mpv. Its source, the patches applied to it and the scripts that build it are in the mpvkit directory of the Plankton repository, which is also where the built libraries are published.")
            }

            Section("Source") {
                rows(source)
            }

            Section("Server") {
                rows(server)
            }

            Section("Networking") {
                rows(networking)
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rows(_ acknowledgements: [Acknowledgement]) -> some View {
        ForEach(acknowledgements) { acknowledgement in
            Link(destination: acknowledgement.url) {
                LabeledContent {
                    if let license = acknowledgement.license {
                        Text(license)
                    }
                } label: {
                    Text(acknowledgement.name)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
