import Foundation
import CoreLocation
import Combine

/// Manages GPS location and compass heading.
/// Includes a simple Kalman filter to smooth GPS jitter and
/// a heading smoother for stable arrow direction.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var heading: Double = 0          // degrees from true north
    @Published var locationError: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var gpsAccuracy: Double = 999    // horizontal accuracy in meters

    // MARK: - Kalman Filter State
    // All variances are in degrees² so they stay comparable to the measurement variance.
    private var kalmanLat: Double?
    private var kalmanLon: Double?
    private var kalmanLatVariance: Double = 0
    private var kalmanLonVariance: Double = 0
    /// Expected movement between GPS fixes: ~3 m at walking pace → (3 / 111320)² degrees²
    private let processNoise: Double = 7.5e-10
    private let metersPerDegree: Double = 111_320

    // MARK: - Heading Smoother
    private var headingHistory: [Double] = []
    private let headingSmoothingWindow = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = kCLHeadingFilterNone
        manager.activityType = .otherNavigation
    }

    // MARK: - Public API

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - Kalman Filter

    private func kalmanFilter(measurement: Double, measurementVariance: Double, current: inout Double?, variance: inout Double) -> Double {
        guard let prior = current else {
            // First measurement — initialize
            current = measurement
            variance = measurementVariance
            return measurement
        }

        // Predict step (assume constant position)
        let predictedVariance = variance + processNoise

        // Update step
        let kalmanGain = predictedVariance / (predictedVariance + measurementVariance)
        let filtered = prior + kalmanGain * (measurement - prior)
        variance = (1 - kalmanGain) * predictedVariance

        current = filtered
        return filtered
    }

    // MARK: - Heading Smoother (circular mean)

    private func smoothHeading(_ newHeading: Double) -> Double {
        headingHistory.append(newHeading)
        if headingHistory.count > headingSmoothingWindow {
            headingHistory.removeFirst()
        }

        // Circular mean to avoid 359°/1° jump issues
        var sinSum = 0.0
        var cosSum = 0.0
        for h in headingHistory {
            sinSum += sin(h * .pi / 180)
            cosSum += cos(h * .pi / 180)
        }
        let avgRad = atan2(sinSum / Double(headingHistory.count),
                           cosSum / Double(headingHistory.count))
        var avgDeg = avgRad * 180 / .pi
        if avgDeg < 0 { avgDeg += 360 }
        return avgDeg
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Reject clearly bad readings (accuracy > 100m is unreliable)
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100 else { return }

        // Convert accuracy (meters) to measurement variance in degrees²
        let accuracyDegrees = location.horizontalAccuracy / metersPerDegree
        let measurementVariance = accuracyDegrees * accuracyDegrees

        let filteredLat = kalmanFilter(measurement: location.coordinate.latitude,
                                        measurementVariance: measurementVariance,
                                        current: &kalmanLat, variance: &kalmanLatVariance)
        let filteredLon = kalmanFilter(measurement: location.coordinate.longitude,
                                        measurementVariance: measurementVariance,
                                        current: &kalmanLon, variance: &kalmanLonVariance)

        DispatchQueue.main.async {
            self.currentLocation = CLLocationCoordinate2D(latitude: filteredLat, longitude: filteredLon)
            self.gpsAccuracy = location.horizontalAccuracy
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negative accuracy means the compass reading is invalid (calibration needed)
        guard newHeading.headingAccuracy >= 0 else { return }

        let rawHeading = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading

        let smoothed = smoothHeading(rawHeading)

        DispatchQueue.main.async {
            self.heading = smoothed
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startTracking()
            case .denied, .restricted:
                self.locationError = "Localisation refusée. Active-la dans Réglages > Repère."
            default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.locationError = "Erreur GPS : \(error.localizedDescription)"
        }
    }
}
