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
        .init(name: "MPVKit", license: "LGPL-3.0", url: URL(string: "https://github.com/schembora/MPVKit")!),
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
                // naming the project: what ships is a patched mpv, and this is
                // where the corresponding source lives.
                Text("mpv and FFmpeg are used under the LGPL v3.0, without the optional GPL components. Plankton links a patched build of mpv; its source and the patch are in the MPVKit repository above.")
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
