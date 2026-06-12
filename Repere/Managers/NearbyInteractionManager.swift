import Foundation
import NearbyInteraction

/// Manages UWB (Ultra-Wideband) sessions for precise direction + distance.
/// Only works on iPhone 11+ with the U1 chip.
/// Falls back gracefully on unsupported devices.
@available(iOS 16.0, *)
final class NearbyInteractionManager: NSObject, ObservableObject, NISessionDelegate {

    static let shared = NearbyInteractionManager()

    private var sessions: [String: NISession] = [:]  // peerID → NISession
    private var configs: [String: NINearbyPeerConfiguration] = [:]  // peerID → running config

    @Published var uwbSupported: Bool = false

    override private init() {
        super.init()
        uwbSupported = NISession.isSupported
    }

    // MARK: - Public API
    
    private func getOrCreateSession(for peerID: String) -> NISession {
        if let session = sessions[peerID] {
            return session
        }
        let session = NISession()
        session.delegate = self
        sessions[peerID] = session
        return session
    }

    /// Start a UWB session with a peer using their discovery token
    func startSession(for peerID: String, with tokenData: Data) {
        guard NISession.isSupported else { return }

        guard let token = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NIDiscoveryToken.self,
            from: tokenData
        ) else {
            print("❌ Failed to decode NIDiscoveryToken")
            return
        }

        let session = getOrCreateSession(for: peerID)
        let config = NINearbyPeerConfiguration(peerToken: token)
        configs[peerID] = config
        session.run(config)
        print("📡 UWB session started for peer: \(peerID)")
    }

    /// Create a new session and get its discovery token for a specific peer
    func createToken(for peerID: String) -> Data? {
        guard NISession.isSupported else { return nil }
        
        let session = getOrCreateSession(for: peerID)
        
        guard let token = session.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )
    }

    /// Invalidate all active UWB sessions
    func invalidateAll() {
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        configs.removeAll()
    }

    // MARK: - NISessionDelegate

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        
        // Find which peer this session belongs to
        guard let peerID = sessions.first(where: { $0.value === session })?.key else { return }

        var userInfo: [String: Any] = ["peerID": peerID]
        if let distance = object.distance {
            userInfo["distance"] = distance
        }
        if #available(iOS 15.0, *) {
            if let angle = object.horizontalAngle {
                userInfo["horizontalAngle"] = angle
            }
        }

        // Post notification with UWB data — picked up by RadarView
        NotificationCenter.default.post(
            name: .uwbUpdate,
            object: nil,
            userInfo: userInfo
        )
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        print("⚠️ UWB peer removed: \(reason)")
    }

    func sessionWasSuspended(_ session: NISession) {
        print("⏸ UWB session suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        // After a suspension the config must be re-run, otherwise no more updates arrive
        if let peerID = sessions.first(where: { $0.value === session })?.key,
           let config = configs[peerID] {
            session.run(config)
        }
        print("▶️ UWB session resumed")
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        // An invalidated session is dead: drop it so a fresh one can be
        // created on the next token exchange
        if let peerID = sessions.first(where: { $0.value === session })?.key {
            sessions.removeValue(forKey: peerID)
            configs.removeValue(forKey: peerID)
        }
        print("❌ UWB session invalidated: \(error)")
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let uwbUpdate = Notification.Name("com.repere.uwbUpdate")
}
