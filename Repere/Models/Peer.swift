import Foundation
import CoreLocation
import simd

// MARK: - Data sent over Bluetooth P2P
struct PeerLocation: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: TimeInterval
    let displayName: String
    let groupCode: String
}

// MARK: - Peer Model
struct Peer: Identifiable {
    let id: String
    var displayName: String
    var location: CLLocationCoordinate2D?
    var distance: Double?           // meters (from GPS)
    var bearing: Double?            // degrees from true north
    var relativeDirection: Double?  // relative to device heading (arrow rotation)
    var lastUpdate: Date
    var connectionStatus: ConnectionStatus
    var uwbDistance: Double?          // precise UWB distance (meters)
    var uwbRelativeDirection: Double? // precise UWB direction (angle)
    var lastUWBUpdate: Date?

    enum ConnectionStatus: String {
        case connected = "Connecté"
        case nearby    = "Très proche"
        case lost      = "Hors portée"
    }

    // MARK: - Computed Properties

    /// True if we haven't received an update in over 30 seconds
    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 30
    }
    
    /// True if we received UWB data in the last 3 seconds
    var isUWBActive: Bool {
        guard let last = lastUWBUpdate else { return false }
        return Date().timeIntervalSince(last) < 3
    }
    
    var activeDistance: Double? {
        isUWBActive ? uwbDistance : distance
    }
    
    var activeDirection: Double? {
        isUWBActive ? uwbRelativeDirection : relativeDirection
    }

    /// Human-readable distance string
    var displayDistance: String {
        if isUWBActive, let dist = uwbDistance {
            return String(format: "%.1fm", dist)
        }
        guard let dist = distance else { return "..." }
        if dist < 1000 {
            return String(format: "%.0fm", dist)
        } else {
            return String(format: "%.1fkm", dist / 1000)
        }
    }

    /// Color range based on distance
    var distanceColor: DistanceRange {
        let d = activeDistance ?? 999
        if d < 20  { return .veryClose }
        if d < 50  { return .close }
        if d < 150 { return .medium }
        return .far
    }

    enum DistanceRange {
        case veryClose  // < 20m  → green
        case close      // < 50m  → blue/teal
        case medium     // < 150m → orange
        case far        // > 150m → red
    }
}
