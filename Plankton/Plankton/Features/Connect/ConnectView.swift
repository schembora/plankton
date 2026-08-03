//
//  ConnectView.swift
//  Plankton
//
//  First-run screen: enter a server address or pick one found on the local network.
//

import JellyfinAPI
import SwiftUI

struct ConnectView: View {

    @Environment(JellyfinService.self) private var jellyfin

    @State private var serverAddress = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showSignIn = false

    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var isDiscovering = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    addressSection
                    discoverySection
                }
                .padding()
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSignIn) {
                SignInView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "water.waves")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Plankton")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Connect to your Jellyfin server")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 48)
    }

    private var addressSection: some View {
        VStack(spacing: 12) {
            TextField("Server address", text: $serverAddress, prompt: Text("e.g. 192.168.1.5:8096"))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .onSubmit(connect)

            Button(action: connect) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView()
                    }
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(serverAddress.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("On Your Network")
                    .font(.headline)
                Spacer()
                if isDiscovering {
                    ProgressView()
                } else {
                    Button("Search", action: discover)
                        .buttonStyle(.glass)
                }
            }

            ForEach(discoveredServers) { server in
                Button {
                    serverAddress = server.url.absoluteString
                    connect()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(server.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .contentShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }

            if !isDiscovering && discoveredServers.isEmpty {
                Text("No servers found yet")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func connect() {
        errorMessage = nil
        isConnecting = true

        Task {
            do {
                try await jellyfin.validateServer(address: serverAddress)
                showSignIn = true
            } catch JellyfinService.ConnectError.invalidAddress {
                errorMessage = "That doesn't look like a valid server address."
            } catch {
                // The server can't be reached — go into offline mode. Downloads
                // live on the device, and offline mode offers a way back here.
                jellyfin.enterOfflineMode()
            }
            isConnecting = false
        }
    }

    private func discover() {
        isDiscovering = true
        discoveredServers = []

        Task {
            for await server in ServerDiscovery.discover() where !discoveredServers.contains(server) {
                discoveredServers.append(server)
            }
            isDiscovering = false
        }
    }
}
