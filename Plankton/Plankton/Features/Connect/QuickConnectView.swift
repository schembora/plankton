//
//  QuickConnectView.swift
//  Plankton
//
//  Shows a Quick Connect code and waits for another signed-in session to approve it.
//

import SwiftUI

struct QuickConnectView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(\.dismiss) private var dismiss

    @State private var code: String?
    @State private var didFail = false
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if didFail {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Quick Connect didn't finish. The code may have expired before it was approved.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Get a New Code") { attempt += 1 }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                } else if let code {
                    Text(code)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .tracking(6)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .contentTransition(.numericText())

                    Text("Enter this code under Quick Connect in the Jellyfin web client or another signed-in app.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for approval…")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                } else {
                    ProgressView("Requesting a code…")
                }
            }
            .padding(32)
            .frame(maxWidth: 500, maxHeight: .infinity)
            .navigationTitle("Quick Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Leaving the sheet cancels this task, which stops the polling.
            .task(id: attempt) {
                code = nil
                didFail = false
                do {
                    try await jellyfin.signInWithQuickConnect { code = $0 }
                } catch {
                    didFail = true
                }
            }
        }
        .presentationDetents([.medium])
    }
}
