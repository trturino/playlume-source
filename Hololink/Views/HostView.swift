//
//  HostView.swift
//  Moonlight
//
//  Created by Rafael Turino on 2/19/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

public struct HostView: View {
    @EnvironmentObject private var viewModel: MainViewModel

    public var body: some View {
        if let host = viewModel.selectedHost {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        heroCard(for: host)

                        DashboardSection(
                            title: "Actions",
                            subtitle: "Refresh this host, adjust streaming settings, or change its pairing state.",
                            width: geometry.size.width
                        ) {
                            actionTile(
                                title: "Refresh",
                                subtitle: "Update host status and reload the app library.",
                                systemImage: "arrow.clockwise",
                                palette: .hostOnline
                            ) {
                                Task {
                                    await viewModel.updateHost(host: host)
                                    viewModel.refreshAppsFor(host: host)
                                }
                            }

                            if host.pairState == .paired {
                                NavigationLink {
                                    SettingsView(settings: $viewModel.streamSettings)
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    DashboardTile(
                                        title: "Settings",
                                        subtitle: "Tune resolution, bitrate, controls, and audio before you launch.",
                                        systemImage: "gearshape",
                                        palette: .app
                                    ) {
                                        EmptyView()
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                actionTile(
                                    title: "Start Pairing",
                                    subtitle: "Generate a PIN and link this host to the current device.",
                                    systemImage: "link.badge.plus",
                                    palette: .caution
                                ) {
                                    viewModel.tryPairHost(host)
                                }
                                .disabled(viewModel.isPairing(host: host))
                            }
                        }

                        if host.pairState == .paired {
                            DashboardSection(
                                title: "Apps",
                                subtitle: appsSubtitle(for: host),
                                width: geometry.size.width
                            ) {
                                if host.appList.isEmpty {
                                    DashboardTile(
                                        title: "No Apps Available",
                                        subtitle: "Pull the latest app list from the host or check that apps are exposed in Sunshine or GeForce Experience.",
                                        systemImage: "square.grid.2x2",
                                        palette: .hostOffline
                                    ) {
                                        EmptyView()
                                    }
                                } else {
                                    ForEach(sortedApps(for: host), id: \.id) { app in
                                        AppCardView(host: host, app: app)
                                    }
                                }
                            }
                        } else {
                            DashboardSection(
                                title: "Pairing",
                                subtitle: "Unpaired hosts need to be approved before Playlume can browse and launch apps.",
                                width: geometry.size.width
                            ) {
                                DashboardTile(
                                    title: "Approve This Host",
                                    subtitle: "Start pairing, enter the generated PIN on the PC, then reopen the library here.",
                                    systemImage: "lock.open.display",
                                    palette: .caution
                                ) {
                                    Button {
                                        viewModel.tryPairHost(host)
                                    } label: {
                                        Label(
                                            viewModel.isPairing(host: host) ? "Pairing…" : "Start Pairing",
                                            systemImage: viewModel.isPairing(host: host) ? "progress.indicator" : "link.badge.plus"
                                        )
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(viewModel.isPairing(host: host))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
            }
            .task {
                await viewModel.updateHost(host: host)
            }
            .onAppear {
                viewModel.refreshAppsFor(host: host)
            }
            .refreshable {
                await viewModel.updateHost(host: host)
                viewModel.refreshAppsFor(host: host)
            }
            .navigationTitle(host.name)
            .navigationBarTitleDisplayMode(.inline)
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
        } else {
            Color.clear
        }
    }

    private func heroCard(for host: TemporaryHost) -> some View {
        DashboardHeroCard(
            title: "Overview",
            description: hostDescription(for: host),
            palette: host.state == .online ? .hostOnline : .hostOffline
        ) {
            HStack(spacing: 12) {
                DashboardSummaryPill(title: hostStatus(for: host), systemImage: host.state == .online ? "network" : "exclamationmark.triangle")
                DashboardSummaryPill(title: host.pairState == .paired ? "Paired" : "Needs Pairing", systemImage: host.pairState == .paired ? "checkmark.shield" : "lock")
                DashboardSummaryPill(title: "\(host.appList.count) Apps", systemImage: "square.grid.2x2")
            }
        }
    }

    private func hostDescription(for host: TemporaryHost) -> String {
        let address = host.activeAddress ?? host.localAddress ?? host.address ?? host.externalAddress ?? "No active address"
        return "Current target: \(address)"
    }

    private func hostStatus(for host: TemporaryHost) -> String {
        switch host.state {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        default:
            return "Checking"
        }
    }

    private func appsSubtitle(for host: TemporaryHost) -> String {
        if host.currentGame != nil {
            return "Launch another app or reconnect to the one that is already running."
        }

        return "Choose a title to launch immediately on \(host.name)."
    }

    private func sortedApps(for host: TemporaryHost) -> [TemporaryApp] {
        host.appList.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func actionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        palette: DashboardPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DashboardTile(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                palette: palette
            ) {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
    }
}

struct AppCardView: View {
    @EnvironmentObject private var viewModel: MainViewModel

    let host: TemporaryHost
    let app: TemporaryApp

    var body: some View {
        Button {
            viewModel.stream(app: app)
        } label: {
            DashboardTile(
                title: app.name ?? "Unknown App",
                subtitle: appSubtitle,
                systemImage: app.hdrSupported ? "sparkles.tv" : "play.square.stack",
                palette: .action
            ) {
                HStack(spacing: 8) {
                    if app.id == host.currentGame {
                        statusPill(title: "Running", systemImage: "play.fill")
                    }

                    if app.hdrSupported {
                        statusPill(title: "HDR", systemImage: "sun.max")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if app.id == host.currentGame {
                Button {
                    let httpManager = HttpManager(host: app.host())
                    let httpResponse = HttpResponse()
                    let quitRequest = HttpRequest(for: httpResponse, with: httpManager?.newQuitAppRequest())
                    Task {
                        httpManager?.executeRequestSynchronously(quitRequest)
                    }
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
            }
        }
    }

    private var appSubtitle: String {
        if app.id == host.currentGame {
            return "This app is already active on the host."
        }

        if app.hdrSupported {
            return "Ready to launch with HDR support."
        }

        return "Ready to launch from \(host.name)."
    }

    private func statusPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: Capsule())
    }
}
