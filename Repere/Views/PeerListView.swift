import SwiftUI

// MARK: - Peer List View
struct PeerListView: View {
    let peers: [Peer]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "0A0A1A").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Tes potes")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding()

                if peers.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Aucun pote connecté")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                                PeerRow(peer: peer, isSelected: index == selectedIndex)
                                    .onTapGesture {
                                        selectedIndex = index
                                        dismiss()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Peer Row
struct PeerRow: View {
    let peer: Peer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSelected
                                ? [Color(hex: "6C63FF"), Color(hex: "E942F5")]
                                : [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Text(String(peer.displayName.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            // Name + status
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(peer.connectionStatus.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            // Distance + mini arrow
            VStack(alignment: .trailing, spacing: 4) {
                Text(peer.displayDistance)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(distanceColor)

                if peer.connectionStatus == .connected {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .rotationEffect(.degrees(peer.relativeDirection ?? 0))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected
                                ? Color(hex: "6C63FF").opacity(0.5)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }

    private var statusColor: Color {
        switch peer.connectionStatus {
        case .connected: return Color(hex: "00F5A0")
        case .nearby:    return Color(hex: "00D9F5")
        case .lost:      return Color(hex: "FF4757")
        }
    }

    private var distanceColor: Color {
        switch peer.distanceColor {
        case .veryClose: return Color(hex: "00F5A0")
        case .close:     return Color(hex: "42E9C2")
        case .medium:    return Color(hex: "F5A623")
        case .far:       return Color(hex: "FF4757")
        }
    }
}
