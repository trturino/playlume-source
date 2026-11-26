//
//  MainFrameViewModel.swift
//  Moonlight
//
//  Created by Rafael Turino on 2/19/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import OrderedCollections
import VideoToolbox

@MainActor
class MainFrameViewModel: NSObject, ObservableObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    
    // Published properties drive the SwiftUI UI
    @Published var hostList: [TemporaryHost] = []
    @Published var selectedHost: TemporaryHost? = nil
    @Published var sortedAppList: [TemporaryApp] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showPairingAlert: Bool = false
    @Published var pairingPin: String = ""
    @Published var navigationTitle: String = "Select Host"
    
    // For box art caching (used in the app grid)
    var boxArtCache = NSCache<TemporaryApp, UIImage>()
    
    // Internal state
    private var showHiddenApps: Bool = false
    private var background: Bool = false
    
    // Dependencies
    var discoveryManager: DiscoveryManager!
    var appAssetManager: AppAssetManager!
    var clientCert: Data?
    var uniqueId: String = ""
    var streamConfig: StreamConfiguration = StreamConfiguration()
    
    // Operation queue (for pairing etc.)
    private var opQueue = OperationQueue()
    
    // Simulated persistent host storage
    private var persistentHostSet: Set<TemporaryHost> = []
    
    override init() {
        super.init()
        setupCrypto()
        loadSavedHosts()
        appAssetManager = AppAssetManager(callback: self)

        discoveryManager = DiscoveryManager(hosts: Array(persistentHostSet), andCallback: self)
        updateNavigationTitle()
        // If there is only one host, select it immediately.
        if persistentHostSet.count == 1, let host = persistentHostSet.first {
            hostClicked(host: host)
        }
    }
    
    // MARK: - Crypto & Initialization
    
    func setupCrypto() {
        CryptoManager.generateKeyPairUsingSSL()
        uniqueId = IdManager.getUniqueId()
        clientCert = CryptoManager.readCertFromFile()
    }
    
    // MARK: - Host Management
    
    func loadSavedHosts() {
        let dataManager = DataManager()
        let hosts = (dataManager.getHosts() as? [TemporaryHost]) ?? []
        for host in hosts {
            persistentHostSet.insert(host)
            if host.activeAddress == nil {
                host.activeAddress = host.localAddress ?? host.externalAddress ?? host.address ?? host.ipv6Address
            }
        }
        hostList = Array(persistentHostSet).sorted { $0.name < $1.name }
        updateNavigationTitle()
    }
    
    nonisolated func updateAllHosts(_ hosts: [Any]!) {
        
    }
    
    nonisolated func receivedAsset(for app: TemporaryApp!) {
    
    }
    
    func updateAllHosts(_ hosts: [TemporaryHost]) {
        Task { @MainActor in
            self.persistentHostSet = Set(hosts)
            self.hostList = hosts.sorted { $0.name < $1.name }
            self.updateHostsUI()
        }
    }
    
    func updateHostsUI() {
        updateHostShortcuts()
        updateNavigationTitle()
    }
    
    func updateHostShortcuts() {

    }
    
    func updateNavigationTitle() {
        if let selected = selectedHost {
            navigationTitle = selected.name
        } else if hostList.isEmpty {
            navigationTitle = "Searching for PCs on your network..."
        } else {
            navigationTitle = "Select Host"
        }
    }
    
    // MARK: - Pairing Methods
    
    nonisolated func startPairing(_ pin: String!) {
//        Task { @MainActor in self.isLoading = true }
//        // Simulate pairing network call
//        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
//            if pin == "1234" {
//                Task { @MainActor in
//                    self.pairSuccessful(serverCert: Data())
//                }
//            } else {
//                Task { @MainActor in
//                    self.pairFailed(message: "Incorrect PIN.")
//                }
//            
//            }
//        }
    }
    
    nonisolated func pairFailed(_ message: String) {
        Task { @MainActor in
            self.errorMessage = message
            self.isLoading = false
        }
    }
    
    nonisolated func pairSuccessful(_ serverCert: Data) {
        Task { @MainActor in
            if var host = self.selectedHost {
                host.serverCert = serverCert
                if let index = self.hostList.firstIndex(where: { $0.id == host.id }) {
                    self.hostList[index] = host
                }
                self.discoveryManager.startDiscovery()
                self.alreadyPaired()
            }
            self.isLoading = false
        }
    }
    
    // MARK: - App List & Updates
    
    nonisolated func alreadyPaired() {
        var host: TemporaryHost!
        Task { @MainActor in
            guard let host = selectedHost else {
                self.isLoading = false
                return
            }
            if !host.appList.isEmpty {
                Task { @MainActor in
                    if self.selectedHost?.id != host.id { self.isLoading = false; return }
                    self.updateAppsForHost(host: host)
                    self.isLoading = false
                }
            }
        }
        Task {
            await self.discoveryManager.pauseDiscovery(for: host)
            let appListResp = ConnectionHelper.getAppList(for: host)
            await self.discoveryManager.resumeDiscovery(for: host)
            if let appListResp = ConnectionHelper.getAppList(for: host) {
                if !appListResp.isStatusOk() || appListResp.getAppList() == nil {
                    Task { @MainActor in
                        if self.selectedHost?.id != host.id { self.isLoading = false; return }
                        self.errorMessage = appListResp.statusMessage
                        // Mark host offline
                        var updatedHost = host
                        updatedHost?.state = .offline
                        self.isLoading = false
                    }
                } else {
                    Task { @MainActor in
                        if let newApps = appListResp.getAppList() as? Set<TemporaryApp> {
                            self.updateApplist(newList: newApps, forHost: host)
                            if self.selectedHost?.id != host.id { self.isLoading = false; return }
                            self.updateAppsForHost(host: host)
                            self.appAssetManager.stopRetrieving()
                            self.appAssetManager.retrieveAssets(from: host)
                            self.isLoading = false
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    self.errorMessage = "No app list response."
                    self.isLoading = false
                }
            }
        }
    }
    
    func updateApplist(newList: Set<TemporaryApp>, forHost host: TemporaryHost) {
        let database = DataManager()
        var newHostAppList = host.appList
        for app in newList {
            if !newHostAppList.contains(app) {
                newHostAppList.insert(app, at: 0)
            } else if let existing = newHostAppList.first(where: { $0.id == app.id }) {
                var updated = existing
                updated.name = app.name
                updated.hdrSupported = app.hdrSupported
                newHostAppList.update(updated, at: 0)
            }
        }
        var appWasRemoved: Bool
        repeat {
            appWasRemoved = false
            for app in newHostAppList {
                if !newList.contains(app) {
                    newHostAppList.remove(app)
                    database.remove(app)
                    appWasRemoved = true
                    break
                }
            }
        } while appWasRemoved
        var updatedHost = host
        updatedHost.appList = newHostAppList
        database.updateApps(forExisting: updatedHost)
        updateHostShortcuts()
    }
    
    func updateAppsForHost(host: TemporaryHost) {
        guard let selected = selectedHost, selected.id == host.id else {
            return
        }
        sortedAppList = Array(host.appList).sorted { $0.name ?? "" < $1.name ?? "" }
        if !showHiddenApps {
            sortedAppList = sortedAppList.filter { !$0.hidden }
        }
    }
    
    // MARK: - Host & Navigation Actions
    
    func showHostSelectionView() {
        appAssetManager.stopRetrieving()
        showHiddenApps = false
        selectedHost = nil
        sortedAppList = []
        updateNavigationTitle()
    }
    
    func hostClicked(host: TemporaryHost) {
        if host.state != .online {
            hostLongClicked(host: host)
            return
        }
        selectedHost = host
        updateNavigationTitle()
        if host.state == .online && host.pairState == .paired && !host.appList.isEmpty {
            alreadyPaired()
            return
        }
        isLoading = true
        Task {
            var currentHost = host
            while currentHost.state == .unknown {
                sleep(1)
            }
            if currentHost.state == .offline {
                Task { @MainActor in
                    self.isLoading = false
                    self.showHostSelectionView()
                }
                return
            }
            let httpManager = HttpManager(host: currentHost)
            let serverInfoResp = ServerInfoResponse()
            self.discoveryManager.pauseDiscovery(for: currentHost)
            httpManager?.executeRequestSynchronously(HttpRequest(
                for: serverInfoResp,
                with: httpManager?.newServerInfoRequest(false),
                fallbackError: 401,
                fallbackRequest: httpManager?.newHttpServerInfoRequest()))
            self.discoveryManager.resumeDiscovery(for: currentHost)
            if !serverInfoResp.isStatusOk() {
                Task { @MainActor in
                    if self.selectedHost?.id != currentHost.id {
                        self.isLoading = false
                        return
                    }
                    self.errorMessage = serverInfoResp.statusMessage
                    var updatedHost = currentHost
                    updatedHost.state = .offline
                    self.isLoading = false
                }
            } else {
                var updatedHost = currentHost
                serverInfoResp.populateHost(updatedHost)
                if updatedHost.pairState == .paired {
                    Task { @MainActor in self.alreadyPaired() }
                } else {
                    self.discoveryManager.stopDiscoveryBlocking()
                    let pairManager = PairManager(manager: httpManager, clientCert: self.clientCert, callback: self)
                    self.opQueue.addOperation(pairManager!)
                }
            }
        }
    }
    
    func hostLongClicked(host: TemporaryHost) {
        // In SwiftUI the long-press action would trigger an ActionSheet.
        // For production, update published properties so that your view presents an action sheet with options (e.g. Wake PC, View All Apps, Test Network, Remove Host, etc.)
        // See the AppGridView below for an example of a context menu.
    }
    
    func addHostClicked(address: String) {
        isLoading = true
        discoveryManager.discoverHost(address) { (host, error) in
            Task { @MainActor in
                self.isLoading = false
                if let newHost = host {
                    self.persistentHostSet.insert(newHost)
                    self.hostList = Array(self.persistentHostSet).sorted { $0.name < $1.name }
                    self.updateHostsUI()
                } else if let error = error {
                    self.errorMessage = error + "\n\nYour device's network connection may be blocking streaming."
                }
            }
        }
    }
    
    // MARK: - Streaming Setup
    
    func prepareToStreamApp(app: TemporaryApp) {
//        streamConfig = StreamConfiguration()
//        if let host = selectedHost {
//            streamConfig.host = host.activeAddress ?? ""
//            streamConfig.httpsPort = 443
//            streamConfig.appID = app.id
//            streamConfig.appName = app.name
//            streamConfig.serverCert = host.serverCert
//        }
//        let dataManager = DataManager()
//        let streamSettings = dataManager.getSettings()
//        streamConfig.frameRate = streamSettings.framerate.intValue
//        streamConfig.height = streamSettings.height.intValue
//        streamConfig.width = streamSettings.width.intValue
//        streamConfig.bitRate = streamSettings.bitrate.intValue
//        streamConfig.optimizeGameSettings = streamSettings.optimizeGames
//        streamConfig.playAudioOnPC = streamSettings.playAudioOnPC
//        streamConfig.useFramePacing = streamSettings.useFramePacing
//        streamConfig.swapABXYButtons = streamSettings.swapABXYButtons
//        streamConfig.multiController = streamSettings.multiController
//        streamConfig.gamepadMask = ControllerSupport.getConnectedGamepadMask(streamConfig)
//        let physicalOutputChannels = Int(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
//        let numberOfChannels = min(streamSettings.audioConfig.intValue, physicalOutputChannels)
//        if numberOfChannels >= 8 {
//            streamConfig.audioConfiguration = 71 // placeholder for 7.1 surround
//        } else if numberOfChannels >= 6 {
//            streamConfig.audioConfiguration = 51 // placeholder for 5.1 surround
//        } else {
//            streamConfig.audioConfiguration = 2  // stereo
//        }
//        streamConfig.serverCodecModeSupport = selectedHost?.serverCodecModeSupport ?? 0
//        
//        switch streamSettings.preferredCodec {
//        case 1: // AV1
//            #if available(iOS 16.0, tvOS 16.0, *)
//            if VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) {
//                streamConfig.supportedVideoFormats |= 1 << 0 // placeholder for AV1_MAIN8
//            }
//            #endif
//            fallthrough
//        case 0, 2: // Auto or HEVC
//            if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) {
//                streamConfig.supportedVideoFormats |= 1 << 1 // placeholder for H265
//            }
//            fallthrough
//        case 3: // H264
//            streamConfig.supportedVideoFormats |= 1 << 2 // placeholder for H264
//        default:
//            break
//        }
//        // Additional logic for HDR and advanced codec configurations…
    }
    
    // MARK: - App Interaction
    
    func appLongClicked(app: TemporaryApp) {
        // In SwiftUI you would present an ActionSheet with options:
        // "Launch/Resume App", "Quit App", "Hide/Show App", etc.
        // For brevity, this logic is encapsulated in your view’s context menu.
    }
    
    func appClicked(app: TemporaryApp) {
        appAssetManager.stopRetrieving()
        if let host = selectedHost, findRunningApp(host: host) != nil {
            appLongClicked(app: app)
        } else {
            prepareToStreamApp(app: app)
            // In production, navigate to your streaming view passing streamConfig.
        }
    }
    
    func findRunningApp(host: TemporaryHost) -> TemporaryApp? {
        for app in host.appList {
            if app.id == host.currentGame { return app }
        }
        return nil
    }
    
    // MARK: - Box Art Caching
    
    static func loadBoxArtForCaching(app: TemporaryApp) -> UIImage? {
        let filePath = AppAssetManager.boxArtPath(for: app) ?? ""
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = cgImage.width, height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let outputImage = context.makeImage() else { return nil }
        return UIImage(cgImage: outputImage)
    }
    
    func updateBoxArtCache(for app: TemporaryApp) {
        if boxArtCache.object(forKey: app) == nil {
            if let image = MainFrameViewModel.loadBoxArtForCaching(app: app) {
                boxArtCache.setObject(image, forKey: app)
            }
        }
    }
    
    // MARK: - Lifecycle & Foreground/Background Handling
    
    func beginForegroundRefresh() {
        if !background {
            updateHosts()
            discoveryManager.resetDiscoveryState()
            discoveryManager.startDiscovery()
            if let host = selectedHost, host.pairState == .paired {
                hostClicked(host: host)
            }
        }
    }
    
    func handleReturnToForeground() {
        background = false
        beginForegroundRefresh()
        handlePendingShortcutAction()
    }
    
    func handleEnterBackground() {
        background = true
        discoveryManager.stopDiscovery()
    }
    
    func handlePendingShortcutAction() {
        // Check for any pending shortcut actions (from AppDelegate) and navigate if needed.
    }
    
    func updateHosts() {
        for host in hostList {
            for app in host.appList {
                Task { @MainActor in
                    self.updateBoxArtCache(for: app)
                }
            }
        }
        updateHostShortcuts()
        updateNavigationTitle()
    }
    
    // MARK: - Toggle App Hidden State
    
    func toggleAppHidden(app: TemporaryApp) {
        if let index = sortedAppList.firstIndex(of: app) {
            var updated = sortedAppList[index]
            updated.hidden.toggle()
            sortedAppList[index] = updated
            if var host = selectedHost, let hostIndex = host.appList.firstIndex(where: { $0.id == app.id }) {
                host.appList.update(updated, at: 0)
            }
        }
    }
}
