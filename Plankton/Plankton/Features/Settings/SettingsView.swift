//
//  SettingsView.swift
//  Plankton
//
//  Server/account info and sign out.
//

import SwiftUI

struct SettingsView: View {

    @Environment(JellyfinService.self) private var jellyfin

    @State private var isSigningOut = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    LabeledContent("Name", value: jellyfin.serverName ?? "Unknown")
                    LabeledContent("Address", value: jellyfin.serverURL?.absoluteString ?? "Unknown")
                }

                Section("Account") {
                    LabeledContent("Signed in as", value: jellyfin.username ?? "Unknown")
                    Button("Sign Out", role: .destructive, action: signOut)
                        .disabled(isSigningOut)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            await jellyfin.signOut()
            isSigningOut = false
        }
    }
}
