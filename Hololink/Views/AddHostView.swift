//
//  AddHostView.swift
//  Hololink
//
//  Created by Rafael Turino on 3/4/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct AddHostView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Binding var isPresented: Bool
    @State private var hostAddress = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        DashboardHeroCard(
                            title: "Add Computer",
                            description: "Enter the local IP address or hostname of a computer on the same network for initial pairing.",
                            palette: .hero
                        ) {
                            HStack(spacing: 12) {
                                DashboardSummaryPill(title: "Local Network", systemImage: "network")
                                DashboardSummaryPill(title: "Manual Entry", systemImage: "keyboard")
                            }
                        }

                        DashboardSection(
                            title: "Connection",
                            subtitle: "Use the same destination you would enter in Moonlight on another device.",
                            width: geometry.size.width
                        ) {
                            DashboardTile(
                                title: "Host Address",
                                subtitle: hostAddress.isEmpty ? "IP address or hostname" : hostAddress,
                                systemImage: "desktopcomputer.and.arrow.down",
                                palette: .action
                            ) {
                                TextField("192.168.1.25 or gaming-pc.local", text: $hostAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($isFieldFocused)
                            }

                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
                .navigationTitle("Add Computer")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            submit()
                        }
                        .disabled(trimmedHostAddress.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            isFieldFocused = true
        }
        .alert("Unable to add host", isPresented: $viewModel.errorAddingHost) {
            Button("OK", role: .cancel) {
                viewModel.errorAddingHost = false
            }
        } message: {
            Text(viewModel.addHostErrorMessage)
        }
    }

    private var trimmedHostAddress: String {
        hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedHostAddress.isEmpty else { return }
        viewModel.manuallyDiscoverHost(hostOrIp: trimmedHostAddress)
        isPresented = false
    }
}
