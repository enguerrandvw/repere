import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    let groupCode: String
    let peerCount: Int
    let onLeave: () -> Void

    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "1A1A2E").ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                Text("Paramètres")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                // Group info card
                VStack(spacing: 12) {
                    settingRow(
                        icon: "number",
                        title: "Code du groupe",
                        value: groupCode
                    )
                    Divider().background(Color.white.opacity(0.1))
                    settingRow(
                        icon: "person.2.fill",
                        title: "Potes connectés",
                        value: "\(peerCount)"
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

                // Haptics toggle
                Toggle(isOn: $hapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .foregroundColor(Color(hex: "6C63FF"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vibrations")
                                .foregroundColor(.white)
                            Text("Vibre quand un pote est proche")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .tint(Color(hex: "6C63FF"))
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .onChange(of: hapticsEnabled) { newValue in
                    HapticManager.shared.setEnabled(newValue)
                }

                // How it works
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Color(hex: "6C63FF"))
                        Text("Comment ça marche")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Repère utilise le **Bluetooth** et le **GPS** (satellites) pour localiser tes potes. Aucun réseau mobile nécessaire ! 📡")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 16) {
                        infoChip(icon: "bluetooth", text: "~100m")
                        infoChip(icon: "location.fill", text: "GPS")
                        infoChip(icon: "sensor.tag.radiowaves.forward.fill", text: "UWB")
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Spacer()

                // Leave group button
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onLeave()
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Quitter le groupe")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "FF4757"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "FF4757").opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "FF4757").opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "6C63FF"))
                .frame(width: 24)
            Text(title)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(Color(hex: "6C63FF"))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: "6C63FF").opacity(0.15))
        )
    }
}
