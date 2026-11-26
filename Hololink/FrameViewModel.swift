import Foundation
import OrderedCollections
import SwiftUI

extension TemporaryApp {
    @objc func compareName(_ other: TemporaryApp) -> Bool {
        let name1 = self.name ?? ""
        let name2 = other.name ?? ""
        return name1 == name2
    }
}


@MainActor
final class FrameViewModel: NSObject, ObservableObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    
    // MARK: - Published Properties (observable by the UI)
    @Published var hosts: [TemporaryHost] = []
    @Published var selectedHost: TemporaryHost?
    @Published var sortedAppList: [TemporaryApp] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// This configuration is prepared when the user selects an app to stream.
    @Published var streamConfig: StreamConfiguration?
    
    // MARK: - Internal Properties
    private var discoveryManager: DiscoveryManager?
    private var appAssetManager: AppAssetManager?
    private var dataManager: DataManager?
    private let opQueue = OperationQueue()
    
    private var clientCert: Data?
    private var uniqueId: String?
    
    // MARK: - Initialization
    override init() {
        super.init()
        Task { @MainActor in
            await self.setup()
        }
    }
    
    /// Setup the view model by initializing crypto, reading saved settings/hosts,
    /// and initializing the discovery and app asset managers.
    @MainActor
    private func setup() async {
        // Setup crypto (this is assumed to be synchronous)
        CryptoManager.generateKeyPairUsingSSL()
        uniqueId = IdManager.getUniqueId()
        clientCert = CryptoManager.readCertFromFile()
        
        // Initialize the data manager and retrieve saved hosts.
        dataManager = DataManager()
        await retrieveSavedHosts()
        
        // Initialize the discovery manager with our current host list.
        discoveryManager = DiscoveryManager(hosts: hosts, andCallback: self)
        appAssetManager = AppAssetManager(callback: self)
    }
    
    /// Retrieve saved hosts from persistent storage and initialize their non‑persistent state.
    @MainActor
    func retrieveSavedHosts() async {
        guard let dm = dataManager else { return }
        // Assume getHosts returns an NSArray of TemporaryHost objects.
        let savedHosts = (dm.getHosts() as? [TemporaryHost]) ?? []
        for host in savedHosts {
            // Set the active address using our priority chain.
            if host.activeAddress == nil {
                host.activeAddress = host.localAddress ?? host.externalAddress ?? host.address ?? host.ipv6Address
            }
        }
        self.hosts = savedHosts
    }
    
    // MARK: - DiscoveryCallback
    /// Called (from Objective‑C code) when a new set of hosts has been discovered.
    @objc func updateAllHosts(_ hosts: [Any]) {
        guard let tempHosts = hosts as? [TemporaryHost] else { return }
        Task { @MainActor in
            self.hosts = tempHosts
        }
    }
    
    // MARK: - PairCallback
    /// Called when pairing is started; for example, update the UI to display the provided PIN.
    @objc func startPairing(_ PIN: String) {
        Task { @MainActor in
            // In your SwiftUI view you could observe a published property for the pairing PIN.
            // For now we clear any previous error message.
            self.errorMessage = nil
            // You might also set a @Published pairingPIN property if needed.
        }
    }
    
    /// Called when pairing succeeds. Store the returned server certificate and continue.
    @objc func pairSuccessful(_ serverCert: Data) {
        Task { @MainActor in
            self.selectedHost?.serverCert = serverCert
            // After successful pairing, update the app list.
            await self.alreadyPaired()
        }
    }
    
    /// Called when pairing fails. Update the error message for the UI.
    @objc func pairFailed(_ message: String) {
        Task { @MainActor in
            self.errorMessage = message
        }
    }
    
    /// Called when the host is already paired. Either use a cached app list or request a refresh.
    @objc func alreadyPaired() {
        Task { @MainActor in
            guard let host = self.selectedHost else {
                self.isLoading = false
                return
            }
            // If we already have an app list cached, update the UI immediately.
            if !host.appList.isEmpty {
                self.sortedAppList = host.appList.elements.sorted(by: { $0.compareName($1) })
            }
            // Then, asynchronously fetch a fresh app list.
            self.isLoading = true
            await self.fetchAppList(for: host)
        }
    }
    
    // MARK: - AppAssetCallback
    /// Called when an asset for an app (such as box art) is received.
    @objc nonisolated func receivedAsset(for app: TemporaryApp) {
        Task { @MainActor in
            // In this sample we simply notify observers.
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Host & App Actions
    /// Called when the user selects (clicks) a host.
    @objc func hostClicked(_ host: TemporaryHost) {
        Task { @MainActor in
            self.selectedHost = host
            // If the host is online, paired, and has a cached app list, use the fast path.
            if host.state == .online && host.pairState == .paired && !host.appList.isEmpty {
                await self.alreadyPaired()
            } else {
                // Otherwise, show a loading state and fetch server info.
                self.isLoading = true
                await self.fetchServerInfo(for: host)
            }
        }
    }
    
    /// Asynchronously fetch server info for the given host and then either continue pairing or load apps.
    private func fetchServerInfo(for host: TemporaryHost) async {
        let hMan = HttpManager(host: host)
        let serverInfoResp = ServerInfoResponse()
        
        // Pause discovery for this host during the network request.
        self.discoveryManager?.pauseDiscovery(for: host)
        
        // Execute the request on a background queue.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                hMan?.executeRequestSynchronously(HttpRequest(for: serverInfoResp,
                                                              with: hMan?.newServerInfoRequest(false),
                                                                                 fallbackError: 401,
                                                                                 fallbackRequest: hMan?.newHttpServerInfoRequest()))
                self.discoveryManager?.resumeDiscovery(for: host)
                DispatchQueue.main.async {
                    if !serverInfoResp.isStatusOk() {
                        self.errorMessage = serverInfoResp.statusMessage
                        host.state = .offline
                        self.isLoading = false
                    } else {
                        serverInfoResp.populateHost(host)
                        if host.pairState == .paired {
                            Task { await self.alreadyPaired() }
                        } else {
                            // Initiate pairing by stopping discovery and starting the pair manager.
                            self.discoveryManager?.stopDiscoveryBlocking()
                            let pMan = PairManager(manager: hMan,
                                                   clientCert: self.clientCert ?? Data(),
                                                   callback: self)
                            if pMan != nil {
                                self.opQueue.addOperation(pMan!)
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    /// Asynchronously fetch the app list for a host.
    private func fetchAppList(for host: TemporaryHost) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // Pause discovery for this host while fetching the app list.
                self.discoveryManager?.pauseDiscovery(for: host)
                let appListResp = ConnectionHelper.getAppList(for: host)
                self.discoveryManager?.resumeDiscovery(for: host)
                
                DispatchQueue.main.async {
                    if !(appListResp?.isStatusOk() ?? false) || appListResp?.getAppList() == nil {
                        self.errorMessage = appListResp?.statusMessage
                        host.state = .offline
                    } else {
                        self.updateApplist(appListResp?.getAppList() as! NSSet, for: host)
                        self.sortedAppList = host.appList.elements.sorted(by: { $0.compareName($1) })
                    }
                    self.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
    
    /// Update the app list for a given host based on a new list (from network).
    @MainActor
    func updateApplist(_ newList: NSSet, for host: TemporaryHost) {
        guard let dm = dataManager else { return }
        // Begin with the current app list.
        var newHostAppSet = Set(host.appList)
        for case let app as TemporaryApp in newList {
            if let existing = newHostAppSet.first(where: { $0.id == app.id }) {
                // Update existing app info.
                existing.name = app.name
                existing.hdrSupported = app.hdrSupported
            } else {
                // Append new app.
                app.setHost(host)
                newHostAppSet.insert(app)
            }
        }
        // Remove any apps that are no longer present.
        let newIDs = (newList as? Set<TemporaryApp>)?.compactMap { $0.id } ?? []
        newHostAppSet = newHostAppSet.filter { app in
            guard let id = app.id else { return false }
            return newIDs.contains(id)
        }
        host.appList = OrderedSet(newHostAppSet)
        dm.updateApps(forExisting: host)
    }
    
    /// Called when the user wants to manually add a host by IP address.
    @objc func addHostManually(address: String) {
        Task { @MainActor in
            self.isLoading = true
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    self.discoveryManager?.discoverHost(address, withCallback: { discoveredHost, error in
                        DispatchQueue.main.async {
                            if let host = discoveredHost {
                                self.hosts.append(host)
                            } else if let error = error {
                                self.errorMessage = error
                            }
                            self.isLoading = false
                            continuation.resume()
                        }
                    })
                }
            }
        }
    }
    
    /// Prepares the streaming configuration from the given app.
    /// This function reads settings (from the data manager) and configures a StreamConfiguration.
    @objc func prepareToStream(app: TemporaryApp) {
        Task { @MainActor in
            let host = app.host()
            let config = StreamConfiguration()
            config.host = host?.activeAddress
            config.httpsPort = host?.httpsPort ?? 0
            config.appID = app.id
            config.appName = app.name
            config.serverCert = host!.serverCert
            
            if let settings = dataManager?.getSettings() {
                config.frameRate = Int32(Int(settings.framerate))
                config.height = Int32(settings.height)
                config.width = Int32(settings.width)
                config.bitRate = Int32(settings.bitrate)
                config.optimizeGameSettings = settings.optimizeGames
                config.playAudioOnPC = settings.playAudioOnPC
                config.useFramePacing = settings.useFramePacing
                config.swapABXYButtons = settings.swapABXYButtons
                config.multiController = settings.multiController
                // Additional settings (audio, video formats, etc.) can be set here.
            }
            config.serverCodecModeSupport = host?.serverCodecModeSupport ?? 0
            self.streamConfig = config
        }
    }
    
    /// Updates the sorted list of apps for the selected host.
    @MainActor
    func updateApps(for host: TemporaryHost) {
        self.sortedAppList = host.appList.elements.sorted(by: { $0.compareName($1) })
    }
    
    // MARK: - Utility Methods for UI State
    @objc func showLoading() {
        Task { @MainActor in
            self.isLoading = true
        }
    }
    
    @objc func hideLoading() {
        Task { @MainActor in
            self.isLoading = false
        }
    }
    
    // MARK: - (Additional methods)
    // You can add further methods here (for example, handling long-press actions on a host or app)
    // by following the same pattern: perform background work asynchronously and update published properties on the main actor.
}
