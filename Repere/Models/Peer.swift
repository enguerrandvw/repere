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
    let accuracy: Double?   // sender's GPS horizontal accuracy (meters)
}

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
    var bluetoothDistance: Double?    // Bluetooth RSSI-based distance (meters)
    var lastBluetoothUpdate: Date?
    var myGPSAccuracy: Double?        // our own GPS accuracy at last direction update (meters)
    var peerGPSAccuracy: Double?      // peer's reported GPS accuracy (meters)

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
    
    /// True if we received Bluetooth RSSI data in the last 5 seconds
    var isBluetoothActive: Bool {
        guard let last = lastBluetoothUpdate else { return false }
        return Date().timeIntervalSince(last) < 5
    }
    
    /// Best available distance: UWB > Bluetooth RSSI > GPS
    var activeDistance: Double? {
        if isUWBActive, let d = uwbDistance { return d }
        if isBluetoothActive, let d = bluetoothDistance { return d }
        return distance
    }
    
    /// Best available direction: UWB > GPS (Bluetooth can't give direction)
    var activeDirection: Double? {
        if isUWBActive, let d = uwbRelativeDirection { return d }
        return relativeDirection
    }
    
    /// Direction is only valid if UWB is actively providing an angle (peer in Field of View),
    /// or if GPS distance exceeds the combined GPS uncertainty of both phones.
    /// When the separation is smaller than the GPS error, the bearing is pure noise —
    /// better to show the hot/cold orb than a random arrow.
    var isDirectionValid: Bool {
        if isUWBActive && uwbRelativeDirection != nil { return true }
        guard let d = distance else { return false }
        let uncertainty = (myGPSAccuracy ?? 15) + (peerGPSAccuracy ?? 15)
        return d > max(15, uncertainty)
    }
    
    /// Which technology is providing the distance
    var distanceSource: String {
        if isUWBActive && uwbDistance != nil { return "UWB" }
        if isBluetoothActive && bluetoothDistance != nil { return "BLE" }
        return "GPS"
    }

    /// Human-readable distance string
    var displayDistance: String {
        guard let dist = activeDistance else { return "..." }
        if dist < 1 {
            return String(format: "%.0fcm", dist * 100)
        } else if dist < 100 {
            return String(format: "%.1fm", dist)
        } else if dist < 1000 {
            return String(format: "%.0fm", dist)
        } else {
            return String(format: "%.1fkm", dist / 1000)
        }
    }

    /// Color range based on distance
    var distanceColor: DistanceRange {
        let d = activeDistance ?? 999
        if d < 5   { return .veryClose }
        if d < 20  { return .close }
        if d < 50  { return .medium }
        return .far
    }

    enum DistanceRange {
        case veryClose  // < 5m  → green
        case close      // < 20m → blue/teal
        case medium     // < 50m → orange
        case far        // > 50m → red
    }
}
