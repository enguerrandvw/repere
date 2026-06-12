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

    /// Create a new group and start advertising + browsing
    func createGroup() -> String {
        let code = String(format: "%04d", Int.random(in: 0...9999))
        groupCode = code
        startSession()
        startAdvertising()
        startBrowsing()
        return code
    }

    /// Join an existing group by code
    func joinGroup(code: String) {
        groupCode = code
        startSession()
        startAdvertising()
        startBrowsing()
    }

    /// Disconnect from everything
    func disconnect() {
        sendTimer?.invalidate()
        sendTimer = nil
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
    func updatePeerDirections(from myLocation: CLLocationCoordinate2D, heading: Double) {
        for i in peers.indices {
            guard let peerLocation = peers[i].location else { continue }

            let bearing = DirectionCalculator.bearing(from: myLocation, to: peerLocation)
            let distance = DirectionCalculator.distance(from: myLocation, to: peerLocation)
            let rawRelative = DirectionCalculator.relativeDirection(bearing: bearing, heading: heading)

            peers[i].bearing = bearing
            peers[i].distance = distance
            
            // Smooth the relative direction to avoid jittery arrow
            if let prev = peers[i].relativeDirection {
                let diff = DirectionCalculator.shortestAngleDiff(from: prev, to: rawRelative)
                peers[i].relativeDirection = prev + diff * 0.3 // 30% interpolation per tick
            } else {
                peers[i].relativeDirection = rawRelative
            }
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

    private func sendLocation(locationManager: LocationManager) {
        guard let location = locationManager.currentLocation,
              let session = session,
              !session.connectedPeers.isEmpty else { return }

        let payload = PeerLocation(
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: Date().timeIntervalSince1970,
            displayName: displayName,
            groupCode: groupCode
        )

        do {
            let data = try JSONEncoder().encode(payload)
            // Use unreliable mode for lower latency (like UDP)
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("❌ Error sending location: \(error)")
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
            } else {
                var newPeer = Peer(
                    id: peerID.displayName,
                    displayName: peerLocation.displayName,
                    lastUpdate: Date(),
                    connectionStatus: .connected
                )
                newPeer.location = coordinate
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
        // Accept invitations from peers in the same group
        if let context = context,
           let info = try? JSONDecoder().decode([String: String].self, from: context),
           info["group"] == groupCode {
            invitationHandler(true, session)
        } else {
            // Accept anyway for V1 simplicity
            invitationHandler(true, session)
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
        guard peerID.displayName != myPeerID.displayName else { return }

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
