import Foundation
import MultipeerConnectivity
import CoreLocation
import Combine

/// Manages Bluetooth / WiFi peer-to-peer communication using MultipeerConnectivity.
/// Exchanges GPS coordinates with nearby peers — NO internet required.
final class MultipeerManager: NSObject, ObservableObject {

    // MARK: - Constants
    private let serviceType = "repere-find" // 1-15 chars, lowercase + hyphens

    // MARK: - MultipeerConnectivity objects
    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var sendTimer: Timer?
    private var reconnectTimer: Timer?

    // MARK: - Published State
    @Published var peers: [Peer] = []
    @Published var isHosting = false
    @Published var isConnected = false
    @Published var groupCode: String = ""
    @Published var displayName: String

    /// Callback for when a UWB discovery token is received from a peer
    var onDiscoveryTokenReceived: ((Data, MCPeerID) -> Void)?

    // MARK: - UWB Token Marker (2-byte prefix to distinguish UWB data from location data)
    private let uwbMarker: Data = Data([0xFF, 0xFE])

    // MARK: - Init

    init(displayName: String) {
        self.displayName = displayName
        self.myPeerID = MCPeerID(displayName: displayName + "_" + UUID().uuidString.prefix(4))
        super.init()
    }

    // MARK: - Public API

    /// Create a new group with the code shown to the user and start advertising + browsing.
    /// The code MUST be set before the advertiser starts: discoveryInfo is captured at creation.
    func createGroup(code: String) {
        groupCode = code
        startSession()
        startAdvertising()
        startBrowsing()
        startReconnectWatchdog()
    }

    /// Join an existing group by code
    func joinGroup(code: String) {
        groupCode = code
        startSession()
        startAdvertising()
        startBrowsing()
        startReconnectWatchdog()
    }

    /// Disconnect from everything
    func disconnect() {
        sendTimer?.invalidate()
        sendTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        peers.removeAll()
        isHosting = false
        isConnected = false
    }

    /// Start sending location every 0.5 seconds
    func startSendingLocation(locationManager: LocationManager) {
        sendTimer?.invalidate()
        sendTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.sendLocation(locationManager: locationManager)
        }
    }

    /// Send UWB discovery token to a specific peer
    func sendDiscoveryToken(_ tokenData: Data, to peer: MCPeerID) {
        guard let session = session else { return }
        var markedData = uwbMarker
        markedData.append(tokenData)
        do {
            try session.send(markedData, toPeers: [peer], with: .reliable)
        } catch {
            print("❌ Error sending UWB token: \(error)")
        }
    }

    /// Recalculate direction and distance for all peers with smooth interpolation
    func updatePeerDirections(from myLocation: CLLocationCoordinate2D, heading: Double, myAccuracy: Double) {
        for i in peers.indices {
            guard let peerLocation = peers[i].location else { continue }

            let rawBearing = DirectionCalculator.bearing(from: myLocation, to: peerLocation)
            let rawDistance = DirectionCalculator.distance(from: myLocation, to: peerLocation)

            // Heavy low-pass on bearing and distance: GPS positions jump a few
            // meters between fixes even when both phones are static. At the 10 Hz
            // tick rate these factors give ~2 s (bearing) and ~1 s (distance)
            // time constants.
            let bearing: Double
            if let prev = peers[i].bearing {
                let diff = DirectionCalculator.shortestAngleDiff(from: prev, to: rawBearing)
                bearing = (prev + diff * 0.05 + 360).truncatingRemainder(dividingBy: 360)
            } else {
                bearing = rawBearing
            }
            peers[i].bearing = bearing

            if let prev = peers[i].distance {
                peers[i].distance = prev + (rawDistance - prev) * 0.1
            } else {
                peers[i].distance = rawDistance
            }

            peers[i].myGPSAccuracy = myAccuracy

            // Relative direction = SMOOTHED bearing + LIVE heading: GPS noise is
            // damped while rotating the phone still moves the arrow instantly
            peers[i].relativeDirection = DirectionCalculator.relativeDirection(bearing: bearing, heading: heading)
        }
    }

    // MARK: - Private Helpers

    private func startSession() {
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }

    private func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["group": groupCode, "name": displayName],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isHosting = true
    }

    private func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    /// MC discovery goes stale after a connection drop: restarting the browser
    /// and advertiser every 10 s while a peer is lost makes reconnection
    /// reliable as soon as the phones are back in radio range
    private func startReconnectWatchdog() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let hasLostPeer = self.peers.contains { $0.connectionStatus == .lost }
            let nobodyConnected = !self.peers.isEmpty
                && !self.peers.contains { $0.connectionStatus == .connected }
            guard hasLostPeer || nobodyConnected else { return }

            print("🔄 Reconnect nudge: restarting discovery")
            self.browser?.stopBrowsingForPeers()
            self.browser?.startBrowsingForPeers()
            self.advertiser?.stopAdvertisingPeer()
            self.advertiser?.startAdvertisingPeer()
        }
    }

    private func sendLocation(locationManager: LocationManager) {
        guard let location = locationManager.currentLocation,
              let session = session,
              !session.connectedPeers.isEmpty else { return }

        // One payload per recipient: each peer gets OUR measurement of the
        // distance to THEM (UWB/BLE), so both phones converge on the best
        // sensor either of them has
        for mcPeer in session.connectedPeers {
            var measuredDistance: Double?
            var measuredSource: String?
            if let peer = peers.first(where: { $0.id == mcPeer.displayName }) {
                if peer.isUWBActive, let d = peer.uwbDistance {
                    measuredDistance = d
                    measuredSource = "UWB"
                } else if peer.isBluetoothActive, let d = peer.bluetoothDistance {
                    measuredDistance = d
                    measuredSource = "BLE"
                }
            }

            let payload = PeerLocation(
                latitude: location.latitude,
                longitude: location.longitude,
                timestamp: Date().timeIntervalSince1970,
                displayName: displayName,
                groupCode: groupCode,
                accuracy: locationManager.gpsAccuracy,
                measuredDistance: measuredDistance,
                measuredSource: measuredSource
            )

            do {
                let data = try JSONEncoder().encode(payload)
                // Use unreliable mode for lower latency (like UDP)
                try session.send(data, toPeers: [mcPeer], with: .unreliable)
            } catch {
                print("❌ Error sending location: \(error)")
            }
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.peers.contains(where: { $0.id == peerID.displayName }) {
                    self.peers.append(Peer(
                        id: peerID.displayName,
                        displayName: peerID.displayName.components(separatedBy: "_").first ?? peerID.displayName,
                        lastUpdate: Date(),
                        connectionStatus: .connected
                    ))
                }
                self.isConnected = true
                print("✅ Connected to: \(peerID.displayName)")
                
                // Exchange UWB tokens
                if #available(iOS 16.0, *) {
                    if let tokenData = NearbyInteractionManager.shared.createToken(for: peerID.displayName) {
                        self.sendDiscoveryToken(tokenData, to: peerID)
                    }
                }

            case .notConnected:
                if let idx = self.peers.firstIndex(where: { $0.id == peerID.displayName }) {
                    self.peers[idx].connectionStatus = .lost
                }
                self.isConnected = self.peers.contains { $0.connectionStatus == .connected }
                print("❌ Disconnected from: \(peerID.displayName)")

            case .connecting:
                print("🔄 Connecting to: \(peerID.displayName)")

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            let tokenData = data.subdata(in: 2..<data.count)
            DispatchQueue.main.async {
                if #available(iOS 16.0, *) {
                    NearbyInteractionManager.shared.startSession(for: peerID.displayName, with: tokenData)
                }
            }
            return
        }

        // Otherwise it's a GPS location update
        guard let peerLocation = try? JSONDecoder().decode(PeerLocation.self, from: data) else { return }
        guard peerLocation.groupCode == groupCode else { return } // ignore other groups

        let coordinate = CLLocationCoordinate2D(
            latitude: peerLocation.latitude,
            longitude: peerLocation.longitude
        )

        DispatchQueue.main.async {
            if let idx = self.peers.firstIndex(where: { $0.id == peerID.displayName }) {
                self.peers[idx].location = coordinate
                self.peers[idx].lastUpdate = Date()
                self.peers[idx].connectionStatus = .connected
                self.peers[idx].displayName = peerLocation.displayName
                self.peers[idx].peerGPSAccuracy = peerLocation.accuracy
                if let measured = peerLocation.measuredDistance {
                    self.peers[idx].remoteMeasuredDistance = measured
                    self.peers[idx].remoteMeasuredSource = peerLocation.measuredSource
                    self.peers[idx].lastRemoteMeasuredUpdate = Date()
                }
            } else {
                var newPeer = Peer(
                    id: peerID.displayName,
                    displayName: peerLocation.displayName,
                    lastUpdate: Date(),
                    connectionStatus: .connected
                )
                newPeer.location = coordinate
                newPeer.peerGPSAccuracy = peerLocation.accuracy
                self.peers.append(newPeer)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Only accept invitations from peers in the same group
        if let context = context,
           let info = try? JSONDecoder().decode([String: String].self, from: context),
           info["group"] == groupCode {
            invitationHandler(true, session)
        } else {
            invitationHandler(false, nil)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Advertising failed: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Only connect to peers in the same group
        guard let info = info, info["group"] == groupCode else { return }
        // Both sides browse AND advertise: if both invite simultaneously the MC
        // handshake often fails. Only the lexicographically smaller peer invites;
        // the other side accepts via its advertiser.
        guard myPeerID.displayName < peerID.displayName else { return }

        print("📡 Found peer: \(info["name"] ?? peerID.displayName)")

        let context = try? JSONEncoder().encode(["group": groupCode])
        browser.invitePeer(peerID, to: session!, withContext: context, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let idx = self.peers.firstIndex(where: { $0.id == peerID.displayName }) {
                self.peers[idx].connectionStatus = .lost
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Browsing failed: \(error)")
    }
}
