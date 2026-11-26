//
//  HostCardView.swift
//  Moonlight
//
//  Created by Rafael Turino on 2/19/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct HostCardView: View {
    @EnvironmentObject private var viewModel: MainViewModel

    let host: TemporaryHost
    let onDelete: () -> Void

    var body: some View {
        Button {
            handlePrimaryAction()
        } label: {
            DashboardTile(
                title: host.name,
                subtitle: hostSubtitle,
                systemImage: hostSystemImage,
                palette: palette
            ) {
                HStack(spacing: 8) {
                    statusPill(title: hostStatusLabel, systemImage: host.state == .online ? "dot.radiowaves.left.and.right" : "moon.zzz")

                    if host.pairState == .paired {
                        statusPill(title: "Paired", systemImage: "checkmark.shield")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(host.updatePending || viewModel.isPairing(host: host))
        .contextMenu {
            Button {
                viewModel.wakeHost(host)
            } label: {
                Label("Wake PC", systemImage: "sun.horizon")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete PC", systemImage: "trash")
            }
        }
        .overlay {
            if host.updatePending {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)

                ProgressView()
                    .controlSize(.large)
            } else if viewModel.isPairing(host: host) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Pairing in Progress")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .alert("Pairing", isPresented: $viewModel.pairingInProgress) {
            Button("Cancel", role: .cancel) {
                viewModel.endPairing()
            }
        } message: {
            Text(
                """
                Enter the following PIN on the host machine:
                \(viewModel.currentPin).

                If your host PC is running Sunshine, enter the PIN in the Sunshine web UI.
                """
            )
        }
    }

    private var palette: DashboardPalette {
        host.state == .online ? .hostOnline : .hostOffline
    }

    private var hostSystemImage: String {
        if host.pairState == .paired {
            return host.state == .online ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark"
        }

        return "lock.desktopcomputer"
    }

    private var hostStatusLabel: String {
        switch host.state {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        default:
            return "Checking"
        }
    }

    private var hostSubtitle: String {
        let address = host.activeAddress ?? host.localAddress ?? host.address ?? host.externalAddress ?? "No active address"
        let pairing: String
        if host.pairState == .paired {
            pairing = host.state == .offline ? "Host offline, unable to browse apps" : "Ready to browse apps"
        } else if host.state == .offline {
            pairing = "Host offline, unable to pair"
        } else {
            pairing = "Select to pair this host"
        }
        return "\(pairing)\n\(address)"
    }
    private func handlePrimaryAction() {
        guard !viewModel.isPairing(host: host) else { return }

        if host.pairState == .paired && host.state == .online {
            viewModel.navigateToHostView(host)
        } else if host.state == .online {
            viewModel.tryPairHost(host)
        }
    }

    private func statusPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: Capsule())
    }
}
