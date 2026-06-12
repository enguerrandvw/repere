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
    let accuracy: Double?           // sender's GPS horizontal accuracy (meters)
    let measuredDistance: Double?   // sender's measured distance to the recipient (UWB/BLE)
    let measuredSource: String?     // "UWB" or "BLE"
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
    // Measurement the PEER's phone made of the distance to us (UWB/BLE),
    // shared over the link: both phones measure the same physical distance,
    // so each should benefit from the other's best sensor
    var remoteMeasuredDistance: Double?
    var remoteMeasuredSource: String? // "UWB" or "BLE"
    var lastRemoteMeasuredUpdate: Date?

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

    /// True if the peer shared a measurement of us in the last 5 seconds
    var isRemoteMeasurementActive: Bool {
        guard let last = lastRemoteMeasuredUpdate else { return false }
        return Date().timeIntervalSince(last) < 5
    }

    /// Best available distance, local or shared by the peer:
    /// UWB (either phone) > BLE (either phone) > GPS
    var activeDistance: Double? {
        if isUWBActive, let d = uwbDistance { return d }
        if isRemoteMeasurementActive, remoteMeasuredSource == "UWB",
           let d = remoteMeasuredDistance { return d }
        if isBluetoothActive, let d = bluetoothDistance { return d }
        if isRemoteMeasurementActive, remoteMeasuredSource == "BLE",
           let d = remoteMeasuredDistance { return d }
        return distance
    }
    
    /// Best available direction: UWB > GPS (Bluetooth can't give direction)
    var activeDirection: Double? {
        if isUWBActive, let d = uwbRelativeDirection { return d }
        return relativeDirection
    }
    
    enum DirectionQuality {
        case precise       // UWB angle, or GPS separation well above the GPS noise
        case approximate   // GPS bearing usable but noisy — shown as a dimmed arrow
        case unavailable   // bearing would be pure noise — hot/cold mode instead
    }

    /// How trustworthy the arrow is.
    /// Indoors the GPS error (±30-60 m) dwarfs the separation, so a GPS arrow
    /// would point randomly — in that case we go full hot/cold mode instead
    /// of showing a misleading arrow.
    var directionQuality: DirectionQuality {
        if isUWBActive && uwbRelativeDirection != nil { return .precise }
        guard let d = distance, relativeDirection != nil, d > 15 else { return .unavailable }
        let uncertainty = (myGPSAccuracy ?? 15) + (peerGPSAccuracy ?? 15)
        if d > uncertainty { return .precise }
        if d > uncertainty / 2 { return .approximate }
        return .unavailable
    }
    
    /// Which technology is providing the distance (local or shared by the peer)
    var distanceSource: String {
        if isUWBActive && uwbDistance != nil { return "UWB" }
        if isRemoteMeasurementActive, remoteMeasuredSource == "UWB",
           remoteMeasuredDistance != nil { return "UWB" }
        if isBluetoothActive && bluetoothDistance != nil { return "BLE" }
        if isRemoteMeasurementActive, let source = remoteMeasuredSource,
           remoteMeasuredDistance != nil { return source }
        return "GPS"
    }

    /// Human-readable distance string. Precision shown matches the precision
    /// the source can actually deliver — displaying "22.7m" from GPS just
    /// makes the number flicker without informing anyone.
    var displayDistance: String {
        guard let dist = activeDistance else { return "..." }
        switch distanceSource {
        case "UWB":
            if dist < 1 { return String(format: "%.0fcm", dist * 100) }
            return String(format: "%.1fm", dist)
        case "BLE":
            return "≈\(Int(dist.rounded()))m"
        default: // GPS: round to 5 m steps
            if dist >= 1000 { return String(format: "≈%.1fkm", dist / 1000) }
            let rounded = max(5, (dist / 5).rounded() * 5)
            return "≈\(Int(rounded))m"
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

/// Is the distance to a peer shrinking or growing? Drives the hot/cold mode.
enum DistanceTrend {
    case approaching
    case receding
    case stable
}
