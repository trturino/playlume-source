//

import SwiftUI
import GameController

struct MainContentView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @State private var addingHost = false
    @State private var isDeletingHost = false
    @State private var hostToDelete: TemporaryHost?
    @State private var newHostIp = ""
    @State private var dimPassthrough = true
    @State private var streamControllerReference = Reference<StreamFrameViewController>()
    @State private var stereoPresentationReady = false
    
    var body: some View {
        if viewModel.activelyStreaming {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    HStack {
                        if viewModel.stereoDepthEnabled && !stereoPresentationReady {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Close", systemImage: "xmark") {
                            viewModel.stopStreaming()
                        }
                        Button("Toggle Dimming", systemImage: dimPassthrough ? "moon.fill" : "moon") {
                            dimPassthrough.toggle()
                        }
                        Button("Stereo Depth", systemImage: viewModel.stereoDepthEnabled ? "visionpro.fill" : "visionpro") {
                            viewModel.stereoDepthEnabled.toggle()
                            if !viewModel.stereoDepthEnabled {
                                stereoPresentationReady = false
                            }
                        }
                        if viewModel.stereoDepthEnabled {
                            StereoDepthModePicker(renderingMode: $viewModel.stereoDepthRenderingMode)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .padding()
                    .glassBackgroundEffect()
                    .frame(maxWidth: .infinity, alignment: .center)

                    ZStack {
                        StreamView(
                            streamConfig: $viewModel.currentStreamConfig,
                            stereoDepthEnabled: .constant(viewModel.stereoDepthEnabled && stereoPresentationReady),
                            controllerReference: streamControllerReference
                        )
                        .handlesGameControllerEvents(matching: .gamepad)
                        .spatialOverlay(alignment: .center) {
                            if viewModel.stereoDepthEnabled {
                                StereoDepthRealityView(
                                    controllerReference: streamControllerReference,
                                    frameRate: Int(viewModel.currentStreamConfig.frameRate),
                                    streamAspectRatio: Double(viewModel.currentStreamConfig.width) / Double(max(viewModel.currentStreamConfig.height, 1)),
                                    model: viewModel.stereoDepthModel,
                                    renderingMode: viewModel.stereoDepthRenderingMode,
                                    configuration: viewModel.stereoDepthConfiguration
                                ) { isReady in
                                    stereoPresentationReady = isReady
                                }
                                .opacity(stereoPresentationReady ? 1 : 0)
                            }
                        }
                    }
                    .aspectRatio(
                        CGSize(
                            width: CGFloat(viewModel.currentStreamConfig.width),
                            height: CGFloat(viewModel.currentStreamConfig.height)
                        ),
                        contentMode: .fit
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30.0))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
            .onAppear {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                let geometryRequest = UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .freeform)
                windowScene.requestGeometryUpdate(geometryRequest)
            }
            .onDisappear {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                let geometryRequest = UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .freeform)
                windowScene.requestGeometryUpdate(geometryRequest)
            }
            .preferredSurroundingsEffect(dimPassthrough ? .systemDark : nil)
            .onDisappear {
                stereoPresentationReady = false
                viewModel.stereoDepthEnabled = false
            }
        } else {
            TabView {
                NavigationSplitView {
                    List(viewModel.hosts, selection: $viewModel.selectedHost) { host in
                        NavigationLink(value: host) {
                            hostRow(for: host)
                        }
                    }
                    .alert("Really delete?", isPresented: $isDeletingHost) {
                        Button("Yes, delete it", role: .destructive) {
                            if let hostToDelete {
                                viewModel.removeHost(hostToDelete)
                                viewModel.selectedHost = nil
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            isDeletingHost = false
                            hostToDelete = nil
                        }
                    }
                    .onChange(of: viewModel.hosts) {
                        // If the hosts list changes and no host is selected,
                        // try to select the first paired host automatically.
                        if viewModel.selectedHost == nil,
                           let firstHost = viewModel.hosts.first(where: { $0.pairState == .paired })
                        {
                            viewModel.selectedHost = firstHost
                        }
                    }
                    .navigationTitle("Computers")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add Server", systemImage: "plus") {
                                addingHost = true
                            }.alert(
                                "Enter server",
                                isPresented: $addingHost
                            ) {
                                TextField("IP or Host", text: $newHostIp)
                                Button("Add") {
                                    addingHost = false
                                    viewModel.manuallyDiscoverHost(hostOrIp: newHostIp)
                                }
                                Button("Cancel", role: .cancel) {
                                    addingHost = false
                                }
                            }.alert(
                                "Unable to add host",
                                isPresented: $viewModel.errorAddingHost
                            ) {
                                Button("Ok", role: .cancel) {
                                    viewModel.errorAddingHost = true
                                }
                            } message: {
                                Text(viewModel.addHostErrorMessage)
                            }
                        }
                    }
                } detail: {
                    if let selectedHost = viewModel.selectedHost {
                        ComputerView(host: selectedHost)
                    }
                    
                }.tabItem {
                    Label("Computers", systemImage: "desktopcomputer")
                }
                .task {
                    viewModel.prepareInitialContent()
                }
                .onAppear {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(viewModel.beginRefresh),
                        name: UIApplication.didBecomeActiveNotification,
                        object: nil
                    )
                }.onDisappear {
                    viewModel.stopRefresh()
                    NotificationCenter.default.removeObserver(self)
                }
            
                SettingsView(settings: $viewModel.streamSettings).tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }
    
    private func hostRow(for host: TemporaryHost) -> some View {
        VStack {
            Label(host.name,
                  systemImage: host.pairState == .paired ?
                      "desktopcomputer" : "lock.desktopcomputer")
                .foregroundColor(.primary)
        }.contextMenu {
            Button {
                viewModel.wakeHost(host)
            } label: {
                Label("Wake PC", systemImage: "sun.horizon")
            }
            Button(role: .destructive) {
                isDeletingHost = true
                hostToDelete = host
            } label: {
                Label("Delete PC", systemImage: "trash")
            }
        }
    }
}
