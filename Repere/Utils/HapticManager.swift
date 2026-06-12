import UIKit
import CoreHaptics

final class HapticManager {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private var lastHapticDate: Date?
    private var hapticsEnabled = true

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
        } catch {
            print("❌ Haptic engine error: \(error)")
        }
    }

    /// Call this with the current distance to a peer.
    /// Provides different vibration intensities based on proximity.
    func proximityFeedback(distance: Double) {
        guard hapticsEnabled else { return }

        // Throttle: max one haptic every 3 seconds
        if let last = lastHapticDate, Date().timeIntervalSince(last) < 3 { return }
        lastHapticDate = Date()

        if distance < 5 {
            foundFeedback()       // 🎉 You found your friend!
        } else if distance < 20 {
            strongPulse()         // 💪 Very close
        } else if distance < 50 {
            softPulse()           // 👋 Getting closer
        }
    }

    private func softPulse() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func strongPulse() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    private func foundFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func setEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
    }
}
