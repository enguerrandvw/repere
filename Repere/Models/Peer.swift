import Foundation
import CoreLocation

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
    var uwbDistance: Float?         // precise UWB distance (meters)
    var uwbDirection: simd_float3?  // precise UWB direction vector

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

    /// Human-readable distance string
    var displayDistance: String {
        if let uwbDist = uwbDistance {
            return String(format: "%.1fm", uwbDist)
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
        let d = uwbDistance.map { Double($0) } ?? distance ?? 999
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
