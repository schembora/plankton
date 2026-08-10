//
//  SettingsView.swift
//  Plankton
//
//  Server/account info and sign out.
//

import SwiftUI

struct SettingsView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(ImageCache.self) private var images
    @Environment(PlaybackSettings.self) private var playback

    @State private var isSigningOut = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var playback = playback

        return NavigationStack {
            List {
                // A picker of one is just a label, so it stays out until there
                // is something to pick between.
                if PlaybackEngineKind.available.count > 1 {
                    Section {
                        Picker("Video", selection: $playback.engine) {
                            ForEach(PlaybackEngineKind.available) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                    } header: {
                        Text("Playback")
                    } footer: {
                        // Said here rather than left to be discovered: the
                        // setting is overridden for live channels, and a
                        // silent exception to a preference is a bug report.
                        Text(playback.engine.explanation
                            + (jellyfin.hasLiveTV ? " Live TV always plays directly, whichever is chosen." : ""))
                    }
                }

                Section {
                    Picker("Wi-Fi", selection: $playback.maxBitrateWiFi) {
                        ForEach(BitrateLimit.allCases) { limit in
                            Text(limit.title).tag(limit)
                        }
                    }

                    Picker("Cellular", selection: $playback.maxBitrateCellular) {
                        ForEach(BitrateLimit.allCases) { limit in
                            Text(limit.title).tag(limit)
                        }
                    }
                } header: {
                    Text("Maximum Bitrate")
                } footer: {
                    // Stated plainly because the intuition runs the other way:
                    // this reads like a quality dial, and lowering it is what
                    // makes the server start converting.
                    Text("The server converts anything above the limit, which is slower to start. Use Maximum unless the connection can't keep up.")
                }

                Section("Server") {
                    LabeledContent("Name", value: jellyfin.serverName ?? "Unknown")
                    LabeledContent("Address", value: jellyfin.serverURL?.absoluteString ?? "Unknown")
                }

                Section("Account") {
                    if jellyfin.isSignedIn {
                        LabeledContent("Signed in as", value: jellyfin.username ?? "Unknown")
                        Button("Sign Out", role: .destructive, action: signOut)
                            .disabled(isSigningOut)
                    } else {
                        // Offline mode without a session — offer a way back
                        // to the connect screen.
                        Button("Change Server Address") {
                            Task { await jellyfin.leaveOfflineMode() }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)

                    NavigationLink("Acknowledgements") {
                        AcknowledgementsView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func signOut() {
        isSigningOut = true
        // Downloads stay on the device — they're not tied to the account. Cached
        // artwork isn't so neutral: it's a picture of what this account's library
        // holds, so it goes with the session.
        images.clear()
        Task {
            await jellyfin.signOut()
            isSigningOut = false
        }
    }
}
