import SwiftUI
import Combine

// MARK: - Main Radar View (the core screen with the arrow)
struct RadarView: View {
    let displayName: String
    let groupCode: String
    let isHost: Bool

    @StateObject private var locationManager = LocationManager()
    @StateObject private var multipeerManager: MultipeerManager
    @StateObject private var bleProximity = BluetoothProximityManager()
    @State private var selectedPeerIndex: Int = 0
    @State private var showSettings = false
    @State private var radarRotation: Double = 0
    @Environment(\.dismiss) private var dismiss

    init(displayName: String, groupCode: String, isHost: Bool) {
        self.displayName = displayName
        self.groupCode = groupCode
        self.isHost = isHost
        _multipeerManager = StateObject(
            wrappedValue: MultipeerManager(displayName: displayName)
        )
    }

    private var selectedPeer: Peer? {
        guard !multipeerManager.peers.isEmpty,
              selectedPeerIndex < multipeerManager.peers.count else { return nil }
        return multipeerManager.peers[selectedPeerIndex]
    }

    var body: some View {
        ZStack {
            // Dark background
            Color(hex: "0A0A1A").ignoresSafeArea()

            // Radar sweep animation
            RadarBackgroundView(rotation: radarRotation)
                .opacity(0.3)

            VStack(spacing: 0) {
                topBar
                Spacer()

                if multipeerManager.peers.isEmpty {
                    waitingView
                } else {
                    arrowSection
                }

                Spacer()
                bottomPeerBar
            }
        }
        .onAppear {
            setupManagers()
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                radarRotation = 360
            }
        }
        .onDisappear {
            multipeerManager.disconnect()
            locationManager.stopTracking()
            bleProximity.stop()
            if #available(iOS 16.0, *) {
                NearbyInteractionManager.shared.invalidateAll()
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateDirections()
            syncBluetoothDistances()
        }
        .onReceive(NotificationCenter.default.publisher(for: .uwbUpdate)) { notification in
            guard let userInfo = notification.userInfo,
                  let peerID = userInfo["peerID"] as? String,
                  let idx = multipeerManager.peers.firstIndex(where: { $0.id == peerID }) else { return }
            
            if let distance = userInfo["distance"] as? Float {
                // Store ultra-precise UWB distance
                multipeerManager.peers[idx].uwbDistance = Double(distance)
                HapticManager.shared.proximityFeedback(distance: Double(distance))
            }
            
            // Store UWB relative direction angle
            if let angle = userInfo["horizontalAngle"] as? Float {
                multipeerManager.peers[idx].uwbRelativeDirection = Double(angle) * 180 / .pi
            } else {
                // If peer is out of UWB Field of View (±60°), the angle is nil.
                // We clear it so we don't use stale UWB data or fall back to noisy GPS.
                multipeerManager.peers[idx].uwbRelativeDirection = nil
            }
            
            multipeerManager.peers[idx].lastUWBUpdate = Date()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                groupCode: groupCode,
                peerCount: multipeerManager.peers.count,
                onLeave: {
                    multipeerManager.disconnect()
                    dismiss()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Groupe \(groupCode)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "00F5A0"))
                        .frame(width: 6, height: 6)
                    let count = multipeerManager.peers.filter { $0.connectionStatus == .connected }.count
                    Text("\(count) connecté\(count > 1 ? "s" : "")")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Waiting for Peers
    private var waitingView: some View {
        VStack(spacing: 20) {
            // Scanning pulse animation
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color(hex: "6C63FF").opacity(0.3), lineWidth: 1)
                        .frame(
                            width: CGFloat(80 + i * 50),
                            height: CGFloat(80 + i * 50)
                        )
                        .scaleEffect(radarRotation > 0 ? 1.5 : 0.8)
                        .opacity(radarRotation > 0 ? 0 : 1)
                        .animation(
                            .easeOut(duration: 2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.5),
                            value: radarRotation
                        )
                }

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundColor(Color(hex: "6C63FF"))
            }

            Text("Recherche de potes...")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            Text("Dis à tes potes de rejoindre\nle groupe avec ce code :")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            // Big group code display
            HStack(spacing: 8) {
                ForEach(Array(groupCode.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(hex: "6C63FF").opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.top, 8)

            // Bluetooth info
            HStack(spacing: 6) {
                Image(systemName: "bluetooth")
                    .font(.system(size: 12))
                Text("Bluetooth activé • GPS actif")
                    .font(.system(size: 12))
            }
            .foregroundColor(Color(hex: "6C63FF").opacity(0.6))
            .padding(.top, 4)
        }
    }

    // MARK: - Arrow + Distance Section
    private var arrowSection: some View {
        VStack(spacing: 16) {
            if let peer = selectedPeer {
                // Peer name
                Text(peer.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                // Directional arrow
                ArrowView(
                    direction: peer.activeDirection ?? 0,
                    distance: peer.activeDistance,
                    peerName: peer.displayName,
                    distanceRange: peer.distanceColor,
                    isDirectionValid: peer.isDirectionValid
                )

                // Distance in big text
                Text(peer.displayDistance)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: distanceColors(for: peer.distanceColor),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                // Connection status badge
                HStack(spacing: 6) {
                    Image(systemName: sourceIcon(for: peer.distanceSource))
                    Text("\(peer.connectionStatus.rawValue) • \(peer.distanceSource)")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(
                    peer.connectionStatus == .connected
                        ? Color(hex: "00F5A0")
                        : Color(hex: "FF4757")
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        (peer.connectionStatus == .connected
                            ? Color(hex: "00F5A0")
                            : Color(hex: "FF4757")
                        ).opacity(0.15)
                    )
                )
            }
        }
    }

    // MARK: - Bottom Peer Bar
    private var bottomPeerBar: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 4)

            if multipeerManager.peers.isEmpty {
                Text("Aucun pote connecté")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(
                            Array(multipeerManager.peers.enumerated()),
                            id: \.element.id
                        ) { index, peer in
                            PeerChip(peer: peer, isSelected: index == selectedPeerIndex)
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        selectedPeerIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Setup

    private func setupManagers() {
        locationManager.requestPermission()

        if isHost {
            multipeerManager.createGroup(code: groupCode)
        } else {
            multipeerManager.joinGroup(code: groupCode)
        }

        multipeerManager.startSendingLocation(locationManager: locationManager)
        
        // Start Bluetooth RSSI proximity scanning
        bleProximity.start(displayName: displayName, groupCode: groupCode)
    }

    private func updateDirections() {
        guard let myLocation = locationManager.currentLocation else { return }
        multipeerManager.updatePeerDirections(
            from: myLocation,
            heading: locationManager.heading,
            myAccuracy: locationManager.gpsAccuracy
        )
    }

    /// Sync Bluetooth RSSI distances into peer models
    private func syncBluetoothDistances() {
        let now = Date()
        for i in multipeerManager.peers.indices {
            let peerName = multipeerManager.peers[i].displayName
            // Exact (case-insensitive) name match only — fuzzy "contains" matching
            // could attach another peer's distance ("Alex" vs "Alexandre")
            guard let reading = bleProximity.peerDistances.first(where: {
                $0.key.caseInsensitiveCompare(peerName) == .orderedSame
            })?.value else { continue }

            // Keep the reading's own timestamp: stamping Date() here would make
            // a frozen BLE reading look fresh forever and mask the GPS distance
            guard now.timeIntervalSince(reading.updatedAt) < 5 else { continue }
            multipeerManager.peers[i].bluetoothDistance = reading.distance
            multipeerManager.peers[i].lastBluetoothUpdate = reading.updatedAt
        }
    }
    
    private func sourceIcon(for source: String) -> String {
        switch source {
        case "UWB": return "wave.3.right"
        case "BLE": return "bluetooth"
        default:    return "location.fill"
        }
    }

    private func distanceColors(for range: Peer.DistanceRange) -> [Color] {
        switch range {
        case .veryClose: return [Color(hex: "00F5A0"), Color(hex: "00D9F5")]
        case .close:     return [Color(hex: "6C63FF"), Color(hex: "42E9C2")]
        case .medium:    return [Color(hex: "F5A623"), Color(hex: "F56C63")]
        case .far:       return [Color(hex: "FF4757"), Color(hex: "FF6B81")]
        }
    }
}

// MARK: - Peer Chip (bottom bar)
struct PeerChip: View {
    let peer: Peer
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isSelected
                          ? Color(hex: "6C63FF").opacity(0.3)
                          : Color.white.opacity(0.08))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle().stroke(
                            isSelected ? Color(hex: "6C63FF") : Color.clear,
                            lineWidth: 2
                        )
                    )

                Text(String(peer.displayName.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(
                        isSelected ? Color(hex: "6C63FF") : .white.opacity(0.7)
                    )
            }

            Text(peer.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Text(peer.displayDistance)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(chipDistanceColor)
        }
        .frame(width: 70)
    }

    private var chipDistanceColor: Color {
        switch peer.distanceColor {
        case .veryClose: return Color(hex: "00F5A0")
        case .close:     return Color(hex: "42E9C2")
        case .medium:    return Color(hex: "F5A623")
        case .far:       return Color(hex: "FF4757")
        }
    }
}

// MARK: - Radar Background Animation
struct RadarBackgroundView: View {
    let rotation: Double

    var body: some View {
        ZStack {
            // Concentric circles
            ForEach(1..<6, id: \.self) { i in
                Circle()
                    .stroke(Color(hex: "6C63FF").opacity(0.05), lineWidth: 0.5)
                    .frame(
                        width: CGFloat(i) * 80,
                        height: CGFloat(i) * 80
                    )
            }

            // Sweeping radar line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "6C63FF").opacity(0.3), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 2, height: 200)
                .offset(y: -100)
                .rotationEffect(.degrees(rotation))
        }
    }
}
