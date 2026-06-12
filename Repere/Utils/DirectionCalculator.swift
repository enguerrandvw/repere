import Foundation
import CoreLocation

struct DirectionCalculator {

    /// Calculate bearing (azimuth) from one coordinate to another.
    /// Returns degrees 0-360 where 0 = North.
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude.degreesToRadians
        let lat2 = to.latitude.degreesToRadians
        let dLon = (to.longitude - from.longitude).degreesToRadians

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearing = atan2(y, x).radiansToDegrees
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Calculate distance between two coordinates using the Haversine formula.
    /// Returns distance in meters.
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0 // Earth's radius in meters
        let lat1 = from.latitude.degreesToRadians
        let lat2 = to.latitude.degreesToRadians
        let dLat = (to.latitude - from.latitude).degreesToRadians
        let dLon = (to.longitude - from.longitude).degreesToRadians

        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return R * c
    }

    /// Calculate relative direction for the arrow.
    /// `bearing`: absolute bearing to target (degrees from north).
    /// `heading`: current device heading (degrees from north).
    /// Returns angle in degrees where 0 = straight ahead on screen.
    static func relativeDirection(bearing: Double, heading: Double) -> Double {
        var relative = bearing - heading
        while relative > 180  { relative -= 360 }
        while relative < -180 { relative += 360 }
        return relative
    }
    /// Shortest signed angular difference (handles 359° → 1° wrap correctly)
    static func shortestAngleDiff(from a: Double, to b: Double) -> Double {
        var diff = b - a
        while diff > 180  { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }
}

// MARK: - Angle Conversion Helpers
extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
