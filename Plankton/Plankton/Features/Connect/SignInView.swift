//
//  SignInView.swift
//  Plankton
//
//  Username/password sign-in against the pending server, plus Quick Connect when available.
//

import SwiftUI

struct SignInView: View {

    @Environment(JellyfinService.self) private var jellyfin

    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var isQuickConnectAvailable = false
    @State private var showQuickConnect = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case username, password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(jellyfin.pendingServerName ?? "Jellyfin Server")
                        .font(.title2)
                        .fontWeight(.bold)
                    if let url = jellyfin.pendingServerURL {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 32)

                VStack(spacing: 12) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .onSubmit(signIn)

                    Button(action: signIn) {
                        HStack(spacing: 8) {
                            if isSigningIn {
                                ProgressView()
                            }
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || isSigningIn)

                    if isQuickConnectAvailable {
                        Button("Use Quick Connect") {
                            showQuickConnect = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Sign In")
        .onAppear { focusedField = .username }
        .task { isQuickConnectAvailable = await jellyfin.isQuickConnectEnabled() }
        .sheet(isPresented: $showQuickConnect) {
            QuickConnectView()
        }
    }

    private func signIn() {
        guard !username.isEmpty, !isSigningIn else { return }

        errorMessage = nil
        isSigningIn = true

        Task {
            do {
                // On success `isSignedIn` flips and the root view swaps to the tabs.
                try await jellyfin.signIn(username: username, password: password)
            } catch {
                errorMessage = "Sign in failed. Check your username and password."
                isSigningIn = false
            }
        }
    }
}
