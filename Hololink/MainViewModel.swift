//
//  MainViewModel.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import OrderedCollections
import AVFoundation
import VideoToolbox

@MainActor
class MainViewModel: NSObject, ObservableObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    private static let stereoAudioConfiguration: Int32 = (0x3 << 16) | (2 << 8) | 0xCA
    private static let surround51AudioConfiguration: Int32 = (0x3F << 16) | (6 << 8) | 0xCA
    private static let surround71AudioConfiguration: Int32 = (0x63F << 16) | (8 << 8) | 0xCA

    @Published var hosts: [TemporaryHost] = []
    
    @Published var pairingInProgress = false
    @Published var currentPin = ""
    @Published private(set) var pairingHostID: String?
    
    @Published var errorAddingHost = false
    @Published var addHostErrorMessage = ""
    
    @Published var currentStreamConfig = StreamConfiguration()
    @Published var activelyStreaming = false
    @Published var stereoDepthEnabled = false
    let stereoDepthModel = StereoDepthModel.defaultValue
    let stereoDepthConfiguration = StereoDepthConfiguration.defaultValue
    @Published var stereoDepthRenderingMode = StereoDepthRenderingMode.defaultValue {
        didSet {
            guard !isApplyingPersistedStereoState else { return }
            persistStereoDepthSettings()
        }
    }
    @Published var streamSettings: TemporarySettings
    @Published var isLoading: Bool = false
    
    @Published var isShowingHostPage: Bool = false
    @Published var isShowingSettingsPage: Bool = false
    @Published var selectedHost: TemporaryHost?
    
    private var dataManager: DataManager
    private var discoveryManager: DiscoveryManager? = nil
    private var appManager: AppAssetManager?
    private var boxArtCache: NSCache<TemporaryApp, UIImage>
    private var clientCert: Data
    private var uniqueId: String
    private var hasLoadedSavedHosts = false
    private var hasStartedInitialLoad = false
    
    private var opQueue = OperationQueue()
    private var activePairOperation: Operation?
    private var currentlyPairingHost: TemporaryHost?
    private var isApplyingPersistedStereoState = false
    
    override private init() {
        boxArtCache = NSCache<TemporaryApp, UIImage>()
        dataManager = DataManager()
        // should this be in viewDidLoad and not init?
        CryptoManager.generateKeyPairUsingSSL()
        clientCert = CryptoManager.readCertFromFile()
        uniqueId = IdManager.getUniqueId()
        streamSettings = dataManager.getSettings()
        
        super.init()
        appManager = AppAssetManager(callback: self)
        discoveryManager = DiscoveryManager(hosts: hosts, andCallback: self)
        opQueue.maxConcurrentOperationCount = 1
        loadPersistedStereoDepthSettings()
    }
    
    @objc static func create() -> MainViewModel {
        return MainViewModel()
    }
    
    func setHosts(newHosts: [TemporaryHost]) {
        hosts.removeAll()
        hosts.append(contentsOf: newHosts)
        if let selectedHost {
            self.selectedHost = newHosts.first(where: { $0.id == selectedHost.id })
        }
    }

    private func assignDefaultActiveAddress(to host: TemporaryHost) {
        if host.activeAddress == nil {
            host.activeAddress = host.localAddress
        }
        if host.activeAddress == nil {
            host.activeAddress = host.externalAddress
        }
        if host.activeAddress == nil {
            host.activeAddress = host.address
        }
        if host.activeAddress == nil {
            host.activeAddress = host.ipv6Address
        }
    }

    private func hostsMatch(_ lhs: TemporaryHost, _ rhs: TemporaryHost) -> Bool {
        if lhs.id == rhs.id {
            return true
        }

        let lhsName = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsName = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lhsLocalAddress = lhs.localAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsLocalAddress = rhs.localAddress?.trimmingCharacters(in: .whitespacesAndNewlines)

        return !lhsName.isEmpty &&
            lhsName == rhsName &&
            lhsLocalAddress != nil &&
            lhsLocalAddress == rhsLocalAddress
    }

    private func mergeHost(_ incomingHost: TemporaryHost, into existingHost: TemporaryHost) {
        existingHost.state = incomingHost.state
        existingHost.currentGame = incomingHost.currentGame
        existingHost.httpsPort = incomingHost.httpsPort
        existingHost.isNvidiaServerSoftware = incomingHost.isNvidiaServerSoftware
        existingHost.updatePending = incomingHost.updatePending

        if incomingHost.serverCert != nil {
            existingHost.serverCert = incomingHost.serverCert
        }

        if incomingHost.address != nil {
            existingHost.address = incomingHost.address
        }
        if incomingHost.externalAddress != nil {
            existingHost.externalAddress = incomingHost.externalAddress
        }
        if incomingHost.localAddress != nil {
            existingHost.localAddress = incomingHost.localAddress
        }
        if incomingHost.ipv6Address != nil {
            existingHost.ipv6Address = incomingHost.ipv6Address
        }
        if incomingHost.mac != nil {
            existingHost.mac = incomingHost.mac
        }

        existingHost.serverCodecModeSupport = incomingHost.serverCodecModeSupport

        if !incomingHost.name.isEmpty {
            existingHost.name = incomingHost.name
        }
        if !incomingHost.uuid.isEmpty {
            existingHost.uuid = incomingHost.uuid
        }

        if incomingHost.pairState == .paired || existingHost.serverCert == nil {
            existingHost.pairState = incomingHost.pairState
        }

        if !incomingHost.appList.isEmpty {
            var mergedAppList = OrderedSet<TemporaryApp>()
            for app in incomingHost.appList {
                app.setHost(existingHost)
                mergedAppList.append(app)
            }
            existingHost.appList = mergedAppList
        }

        if incomingHost.activeAddress != nil {
            existingHost.activeAddress = incomingHost.activeAddress
        } else {
            assignDefaultActiveAddress(to: existingHost)
        }

        if existingHost.pairState == .paired {
            dataManager.update(existingHost)
        }
    }

    private func mergeHosts(_ incomingHosts: [TemporaryHost], persistNewHosts: Bool) {
        for incomingHost in incomingHosts {
            assignDefaultActiveAddress(to: incomingHost)

            if let existingHost = hosts.first(where: { hostsMatch($0, incomingHost) }) {
                mergeHost(incomingHost, into: existingHost)
            } else {
                hosts.append(incomingHost)
                if persistNewHosts && incomingHost.pairState == .paired {
                    dataManager.update(incomingHost)
                }
            }
        }

        if let selectedHost {
            self.selectedHost = hosts.first(where: { hostsMatch($0, selectedHost) })
        }
    }
    
    func addHost(newHost: TemporaryHost) {
        mergeHosts([newHost], persistNewHosts: true)
    }

    func removeHost(_ host: TemporaryHost) {
        if hosts.contains(host) {
            discoveryManager?.removeHost(fromDiscovery: host)
            dataManager.remove(host)
            hosts.removeAll(where: { $0 == host })
        }
    }
    
    func wakeHost(_ host: TemporaryHost) {
        WakeOnLanManager.wake(host)
    }
    
    // MARK: App Icons

    nonisolated func receivedAsset(for app: TemporaryApp!) {
        // pass
    }
    
    // MARK: Pairing

    func manuallyDiscoverHost(hostOrIp: String) {
        self.isLoading = true
        print("isLoading: \(isLoading)")
        discoveryManager?.discoverHost(hostOrIp, withCallback: hostMaybeFound)
    }
    
    nonisolated func hostMaybeFound(host: TemporaryHost?, error: String?) {
        Task { @MainActor in
            if let host {
                self.addHost(newHost: host)
                await self.updateHost(host: host)
                
            } else {
                self.errorAddingHost = true
                self.addHostErrorMessage = error ?? "Unknown Error"
            }
            self.isLoading = false
            print("isLoading: \(isLoading)")
        }
    }
    
    func tryPairHost(_ host: TemporaryHost) {
        guard host.state == .online else { return }
        guard pairingHostID == nil, currentlyPairingHost == nil, activePairOperation == nil else { return }

        pairingHostID = host.id
        currentlyPairingHost = host
        discoveryManager?.stopDiscoveryBlocking()
        let httpManager = HttpManager(host: host)
        // do we need to retain this? probably?
        let pairManager = PairManager(manager: httpManager, clientCert: clientCert, callback: self)
        activePairOperation = pairManager
        opQueue.addOperation(pairManager!)
        print("trying to pair")
    }

    func isPairing(host: TemporaryHost) -> Bool {
        pairingHostID == host.id
    }
    
    func navigateToHostView(_ host: TemporaryHost) {
        guard host.state == .online else { return }

        self.selectedHost = host
        self.isShowingHostPage = true
    }
    
    nonisolated func startPairing(_ PIN: String!) {
        Task { @MainActor in
            pairingInProgress = true
            currentPin = PIN
        }
        print("pairing started")
    }
    
    nonisolated func pairSuccessful(_ serverCert: Data!) {
        Task { @MainActor in
            await finishPairing(markPaired: true, serverCert: serverCert, navigateOnSuccess: true)
        }
    }
    
    nonisolated func pairFailed(_ message: String!) {
        endPairing()
    }
    
    nonisolated func alreadyPaired() {
        Task { @MainActor in
            await finishPairing(markPaired: true, navigateOnSuccess: true)
        }
    }
    
    nonisolated func endPairing() {
        Task { @MainActor in
            await finishPairing()
        }
    }

    private func finishPairing(
        markPaired: Bool = false,
        serverCert: Data? = nil,
        navigateOnSuccess: Bool = false
    ) async {
        guard let host = currentlyPairingHost else {
            pairingInProgress = false
            currentPin = ""
            pairingHostID = nil
            activePairOperation = nil
            discoveryManager?.startDiscovery()
            return
        }

        if let serverCert {
            host.serverCert = serverCert
        }
        if markPaired {
            host.pairState = .paired
        }

        objectWillChange.send()
        pairingInProgress = false
        currentPin = ""
        discoveryManager?.startDiscovery()

        await updateHost(host: host)

        if host.pairState == .paired {
            dataManager.update(host)
            if navigateOnSuccess {
                navigateToHostView(host)
            }
        }

        currentlyPairingHost = nil
        pairingHostID = nil
        activePairOperation = nil
    }
    
    func updateHost(host: TemporaryHost) async {
        discoveryManager?.pauseDiscovery(for: host)
        objectWillChange.send()
        host.updatePending = true

        let serverInfoResponse = await Self.fetchServerInfo(for: host)

        discoveryManager?.resumeDiscovery(for: host)
        host.updatePending = false

        if !serverInfoResponse.isStatusOk() {
            host.state = .offline
            objectWillChange.send()
            print("Failed to get server info: \(serverInfoResponse.statusMessage ?? "unknown error")")
            return
        }

        serverInfoResponse.populateHost(host)
        objectWillChange.send()
        await Self.persist(host: host)
    }
    
    func refreshAppsFor(host: TemporaryHost) {
        discoveryManager?.pauseDiscovery(for: host)

        Task {
            let appListResponse = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: ConnectionHelper.getAppList(for: host))
                }
            }

            discoveryManager?.resumeDiscovery(for: host)

            guard appListResponse?.isStatusOk() == true,
                  let serverApps = appListResponse?.getAppList() as? Set<TemporaryApp> else {
                return
            }

            var newAppList = OrderedSet<TemporaryApp>()
            // Only new apps we have received are valid, but keep the old object and state if it exists.
            for serverApp in serverApps {
                var matchFound = false
                for oldApp in host.appList {
                    if serverApp.id == oldApp.id {
                        oldApp.name = serverApp.name
                        oldApp.hdrSupported = serverApp.hdrSupported
                        oldApp.setHost(host)
                        // Ignore hidden, we want to respect the saved state.
                        matchFound = true
                        newAppList.append(oldApp)
                        break
                    }
                }
                if !matchFound {
                    serverApp.setHost(host)
                    newAppList.append(serverApp)
                }
            }

            let removedApps = host.appList.subtracting(newAppList)
            let database = DataManager()
            for removedApp in removedApps {
                database.remove(removedApp)
            }

            database.updateApps(forExisting: host)

            // self.updateHostShortcuts
            host.appList = newAppList
        }
    }

    // MARK: Host discovery

    func prepareInitialContent() {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true

        Task {
            isLoading = true
            let savedHosts = await Self.fetchSavedHosts()
            loadSavedHosts(savedHosts)
            await refreshHosts(showLoader: false)
            isLoading = false
        }
    }

    private func loadSavedHosts(_ savedHosts: [TemporaryHost]) {
        guard !hasLoadedSavedHosts else { return }
        hasLoadedSavedHosts = true

        mergeHosts(savedHosts, persistNewHosts: false)
    }
    
    func updateHosts(showLoader: Bool = true) async {
        if showLoader {
            isLoading = true
        }

        let currentHosts = hosts
        await withTaskGroup(of: Void.self) { group in
            for host in currentHosts {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.updateHost(host: host)
                }
            }
        }

        if showLoader {
            isLoading = false
        }
    }

    func refreshHosts(showLoader: Bool = true) async {
        if showLoader {
            isLoading = true
        }

        restartDiscovery()
        await updateHosts(showLoader: false)

        if showLoader {
            isLoading = false
        }
    }
    
    // Callback from DiscoveryManager
    nonisolated func updateAllHosts(_ newHosts: [Any]!) {
        if let newHosts = newHosts as? [TemporaryHost] {
            Task {
                if await self.activelyStreaming {
                    return
                }
                await mergeHosts(newHosts, persistNewHosts: false)
            }
        }
    }
    
    @objc func beginRefresh() {
        guard !activelyStreaming else { return }
        restartDiscovery()
    }

    func resumeRefreshIfNeeded() {
        guard !activelyStreaming else { return }
        guard hasStartedInitialLoad else { return }
        restartDiscovery()
    }

    private func restartDiscovery() {
        discoveryManager?.stopDiscovery()
        discoveryManager?.resetDiscoveryState()
        discoveryManager?.startDiscovery()
    }
    
    func stopRefresh() {
        discoveryManager?.stopDiscovery()
    }

    private static func fetchSavedHosts() async -> [TemporaryHost] {
        let savedHosts: [TemporaryHost] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let dataManager = DataManager()
                let savedHosts = dataManager.getHosts() as? [TemporaryHost] ?? []
                continuation.resume(returning: savedHosts)
            }
        }

        let pairedHosts = await MainActor.run {
            savedHosts.filter { $0.pairState == .paired }
        }

        let unpairedHosts = await MainActor.run {
            savedHosts.filter { $0.pairState != .paired }
        }

        let dataManager = DataManager()
        for host in unpairedHosts {
            dataManager.remove(host)
        }

        return pairedHosts
    }

    private static func fetchServerInfo(for host: TemporaryHost) async -> ServerInfoResponse {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let httpManager = HttpManager(host: host)
                let serverInfoResponse = ServerInfoResponse()
                let request = HttpRequest(
                    for: serverInfoResponse,
                    with: httpManager?.newServerInfoRequest(false),
                    fallbackError: 401,
                    fallbackRequest: httpManager?.newHttpServerInfoRequest()
                )
                httpManager?.executeRequestSynchronously(request)
                continuation.resume(returning: serverInfoResponse)
            }
        }
    }

    private static func persist(host: TemporaryHost) async {
        guard host.pairState == .paired else { return }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let dataManager = DataManager()
                dataManager.update(host)
                continuation.resume()
            }
        }
    }
    
    // MARK: Stream Control
    
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.allowAirPlay, .defaultToSpeaker])
            try session.setMode(.moviePlayback)
            try session.setActive(true)
            try session.setIntendedSpatialExperience(.headTracked(soundStageSize: .large, anchoringStrategy: .automatic))
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }

    private func suspendBackgroundWorkForStreaming() {
        appManager?.stopRetrieving()
        discoveryManager?.stopDiscovery()
    }

    private func effectiveFrameRate(for requestedFrameRate: Int32) -> Int32 {
        #if os(visionOS)
        return min(requestedFrameRate, 90)
        #else
        guard #available(iOS 10.3, tvOS 10.2, *) else {
            return requestedFrameRate
        }

        let maximumRefreshRate = Int32(UIScreen.main.maximumFramesPerSecond)
        guard maximumRefreshRate > 0 else {
            return requestedFrameRate
        }

        return min(requestedFrameRate, maximumRefreshRate)
        #endif
    }

    private func effectiveResolution(width: Int32, height: Int32, frameRate: Int32) -> (width: Int32, height: Int32) {
        let pixelCount = Int64(width) * Int64(height)

        let maxPixels: Int64
        if frameRate >= 120 {
            maxPixels = Int64(1920 * 1080)
        } else if frameRate >= 90 {
            maxPixels = Int64(2560 * 1440)
        } else {
            return (width, height)
        }

        guard pixelCount > maxPixels, width > 0, height > 0 else {
            return (width, height)
        }

        let scale = sqrt(Double(maxPixels) / Double(pixelCount))
        let scaledWidth = max(Int32((Double(width) * scale).rounded(.down)), 1280)
        let scaledHeight = max(Int32((Double(height) * scale).rounded(.down)), 720)

        return (scaledWidth & ~1, scaledHeight & ~1)
    }

    private func supportedVideoFormats(width: Int32, height: Int32, frameRate: Int32, hdrEnabled: Bool) -> Int32 {
        let av1Main8: Int32 = 0x1000
        let av1Main10: Int32 = 0x2000
        let h265: Int32 = 0x0100
        let h264: Int32 = 0x0001
        let h265Main10: Int32 = 0x0200

        let av1Supported = VideoToolbox.VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        let hevcSupported = VideoToolbox.VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let hdrPlaybackEligible = AVPlayer.eligibleForHDRPlayback

        // Favor decoder simplicity and latency over compression efficiency.
        // HDR needs a 10-bit codec even at high frame rates. Falling back to
        // H.264 here silently requests SDR from an HDR-enabled host.
        if frameRate >= 90 && !hdrEnabled {
            return h264
        }

        var formats: Int32 = h264

        if streamSettings.preferredCodec == .hevc || streamSettings.preferredCodec == .auto || width > 1920 || height > 1080 || hdrEnabled {
            if hevcSupported {
                formats |= h265
            }
        }

        if streamSettings.preferredCodec == .av1 && av1Supported && !hdrEnabled && frameRate <= 60 {
            formats |= av1Main8
        }

        if hdrEnabled && hdrPlaybackEligible && hevcSupported {
            formats |= h265Main10
            if (formats & av1Main8) != 0 && av1Supported {
                formats |= av1Main10
            }
        }

        return formats
    }

    private func effectiveAudioConfiguration() -> Int32 {
        let physicalOutputChannels = Int32(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        let configuredChannels = max(streamSettings.audioConfig, 2)
        let numberOfChannels = min(configuredChannels, physicalOutputChannels)

        if numberOfChannels >= 8 {
            return Self.surround71AudioConfiguration
        }

        if numberOfChannels >= 6 {
            return Self.surround51AudioConfiguration
        }

        return Self.stereoAudioConfiguration
    }

    func stopStreaming() {
        stereoDepthEnabled = false
        activelyStreaming = false
        beginRefresh()
    }

    private func loadPersistedStereoDepthSettings() {
        isApplyingPersistedStereoState = true
        stereoDepthRenderingMode = .restored(from: streamSettings.stereoDepthProfilesJSON)
        isApplyingPersistedStereoState = false
        persistStereoDepthSettings()
    }

    private func persistStereoDepthSettings() {
        let payload = StereoDepthPersistencePayload(
            renderingMode: stereoDepthRenderingMode
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        streamSettings.stereoDepthSelectedModel = stereoDepthModel.rawValue
        streamSettings.stereoDepthProfilesJSON = json
        streamSettings.save()
    }
    
    func stream(app: TemporaryApp) {
        configureAudioSession()
        
        let config = StreamConfiguration()
        
        guard let host = app.host() else {
            return
        }
        
        let effectiveFrameRate = effectiveFrameRate(for: streamSettings.framerate)
        let effectiveResolution = effectiveResolution(width: streamSettings.width, height: streamSettings.height, frameRate: effectiveFrameRate)
        let hdrEnabled = streamSettings.enableHdr

        config.host = host.activeAddress
        config.httpsPort = host.httpsPort
        config.appID = app.id
        config.appName = app.name
        config.serverCert = host.serverCert

        config.frameRate = effectiveFrameRate
        config.height = effectiveResolution.height
        config.width = effectiveResolution.width

        config.bitRate = streamSettings.bitrate
        config.optimizeGameSettings = streamSettings.optimizeGames
        config.playAudioOnPC = streamSettings.playAudioOnPC
        config.useFramePacing = streamSettings.useFramePacing
        config.swapABXYButtons = streamSettings.swapABXYButtons
        config.multiController = streamSettings.multiController
        config.gamepadMask = ControllerSupport.getConnectedGamepadMask(config)
        
        config.audioConfiguration = effectiveAudioConfiguration()
        
        config.serverCodecModeSupport = host.serverCodecModeSupport
        
        // figure out how to nicely import the c++ headers
        
        config.supportedVideoFormats = supportedVideoFormats(
            width: config.width,
            height: config.height,
            frameRate: config.frameRate,
            hdrEnabled: hdrEnabled
        )
        
        currentStreamConfig = config
        suspendBackgroundWorkForStreaming()
        activelyStreaming = true
    }
}
