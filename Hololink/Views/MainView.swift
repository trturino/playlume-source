//
//  MainView.swift
//  Moonlight
//
//  Created by Rafael Turino on 2/19/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel

    @State private var addingHost = false
    @State private var isDeletingHost = false
    @State private var hostToDelete: TemporaryHost?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroCard

                    DashboardSection(
                        title: "Library",
                        subtitle: "Open a paired computer, start pairing for a new one, or remove devices you no longer use.",
                        width: geometry.size.width
                    ) {
                        actionTile(
                            title: "Add Computer",
                            subtitle: "Discover another PC manually.",
                            systemImage: "plus",
                            palette: .action
                        ) {
                            addingHost = true
                        }

                        actionTile(
                            title: "Refresh Hosts",
                            subtitle: refreshTileSubtitle,
                            systemImage: "arrow.clockwise",
                            palette: .hostOnline
                        ) {
                            Task {
                                await viewModel.refreshHosts()
                            }
                        } content: {
                            tileLoadingContent(
                                isLoading: viewModel.isLoading,
                                loadingTitle: "Refreshing Library",
                                idleTitle: "Refresh Now",
                                loadingSystemImage: "progress.indicator"
                            )
                        }
                    }

                    DashboardSection(
                        title: "Computers",
                        subtitle: hostSectionSubtitle,
                        width: geometry.size.width
                    ) {
                        if viewModel.hosts.isEmpty {
                            DashboardTile(
                                title: viewModel.isLoading ? "Looking for Computers" : "No Computers Yet",
                                subtitle: viewModel.isLoading
                                    ? "Scanning saved hosts and checking your network in the background."
                                    : "Add your first host to start browsing apps and streaming.",
                                systemImage: "desktopcomputer",
                                palette: .hostOffline
                            ) {
                                tileLoadingContent(
                                    isLoading: viewModel.isLoading,
                                    loadingTitle: "Scanning Network",
                                    idleTitle: "Add Computer",
                                    loadingSystemImage: "progress.indicator",
                                    idleSystemImage: "plus"
                                )
                                .font(.subheadline.weight(.semibold))
                                .onTapGesture {
                                    guard !viewModel.isLoading else { return }
                                    addingHost = true
                                }
                            }
                        } else {
                            ForEach(viewModel.hosts) { host in
                                HostCardView(host: host, onDelete: {
                                    hostToDelete = host
                                    isDeletingHost = true
                                })
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .animation(.default, value: viewModel.isLoading)
        }
        .task {
            viewModel.prepareInitialContent()
        }
        .onAppear {
            viewModel.resumeRefreshIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.resumeRefreshIfNeeded()
            case .inactive, .background:
                viewModel.stopRefresh()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $addingHost) {
            AddHostView(isPresented: $addingHost)
                .environmentObject(viewModel)
        }
        .alert("Really delete?", isPresented: $isDeletingHost, presenting: hostToDelete) { host in
            Button("Delete", role: .destructive) {
                viewModel.removeHost(host)
                if viewModel.selectedHost?.id == host.id {
                    viewModel.selectedHost = nil
                }
                hostToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                hostToDelete = nil
            }
        } message: { host in
            Text("Remove \(host.name) from this device?")
        }
        .alert("Unable to add host", isPresented: $viewModel.errorAddingHost) {
            Button("OK", role: .cancel) {
                viewModel.errorAddingHost = false
            }
        } message: {
            Text(viewModel.addHostErrorMessage)
        }
    }

    private var refreshTileSubtitle: String {
        viewModel.isLoading
            ? "Updating saved hosts without interrupting the dashboard."
            : "Scan your network again and refresh each saved host."
    }

    private var heroStatusPill: some View {
        Group {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)

                    Text("Refreshing")
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.14), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func tileLoadingContent(
        isLoading: Bool,
        loadingTitle: String,
        idleTitle: String,
        loadingSystemImage: String,
        idleSystemImage: String? = nil
    ) -> some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingTitle)
            }
        } else if let idleSystemImage {
            Label(idleTitle, systemImage: idleSystemImage)
        } else {
            Text(idleTitle)
        }
    }

    private var heroCard: some View {
        DashboardHeroCard(
            title: "Computers",
            description: "Manage paired PCs, discover new hosts, and move from browsing to launching without switching between list and detail layouts.",
            palette: .hero
        ) {
            HStack(spacing: 12) {
                DashboardSummaryPill(title: "\(viewModel.hosts.count) Saved", systemImage: "desktopcomputer")
                DashboardSummaryPill(title: "\(onlineHostCount) Online", systemImage: "network")
                DashboardSummaryPill(title: "\(pairedHostCount) Paired", systemImage: "lock.open.display")
                heroStatusPill
            }
        }
    }

    private var onlineHostCount: Int {
        viewModel.hosts.filter { $0.state == .online }.count
    }

    private var pairedHostCount: Int {
        viewModel.hosts.filter { $0.pairState == .paired }.count
    }

    private var hostSectionSubtitle: String {
        if viewModel.hosts.isEmpty {
            return "Your saved hosts will appear here once discovery succeeds."
        }

        return "Each card exposes status, address details, and the next action at a glance."
    }

    private func actionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        palette: DashboardPalette,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            DashboardTile(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                palette: palette
            ) {
                content()
            }
        }
        .buttonStyle(.plain)
    }
}
