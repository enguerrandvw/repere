import SwiftUI

// MARK: - Directional Arrow Component
struct ArrowView: View {
    let direction: Double           // degrees, 0 = straight ahead
    let distance: Double?           // meters
    let peerName: String
    let distanceRange: Peer.DistanceRange

    let showArrow: Bool             // true if we have a reliable direction

    @State private var pulse = false
    @State private var glow = false

    private var arrowColors: [Color] {
        switch distanceRange {
        case .veryClose: return [Color(hex: "00F5A0"), Color(hex: "00D9F5")]
        case .close:     return [Color(hex: "6C63FF"), Color(hex: "42E9C2")]
        case .medium:    return [Color(hex: "F5A623"), Color(hex: "F56C63")]
        case .far:       return [Color(hex: "FF4757"), Color(hex: "FF6B81")]
        }
    }

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(
                    LinearGradient(colors: arrowColors, startPoint: .top, endPoint: .bottom),
                    lineWidth: 2
                )
                .frame(width: 220, height: 220)
                .opacity(glow ? 0.8 : 0.3)
                .scaleEffect(glow ? 1.05 : 1.0)

            // Concentric radar circles
            ForEach(1..<4, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(
                        width: CGFloat(i) * 60 + 40,
                        height: CGFloat(i) * 60 + 40
                    )
            }

            if showArrow {
                // The arrow
                ArrowShape()
                    .fill(
                        LinearGradient(
                            colors: arrowColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 60, height: 120)
                    .shadow(color: arrowColors[0].opacity(0.5), radius: 20)
                    .rotationEffect(.degrees(direction))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: direction)
                    .scaleEffect(pulse ? 1.05 : 1.0)

                // Center dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            } else {
                // Direction unknown indicator (Hot/Cold radar)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: arrowColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: arrowColors[0].opacity(0.5), radius: 20)
                        .scaleEffect(pulse ? 1.2 : 1.0)
                        
                    Image(systemName: "questionmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 240, height: 240)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
                glow = true
            }
        }
    }
}

// MARK: - Custom Arrow Shape
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Arrow pointing UP
        path.move(to: CGPoint(x: w * 0.5, y: 0))             // Tip
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.45))  // Right wing
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.35))   // Right notch
        path.addLine(to: CGPoint(x: w * 0.6, y: h))           // Right bottom
        path.addLine(to: CGPoint(x: w * 0.4, y: h))           // Left bottom
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.35))   // Left notch
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.45))  // Left wing
        path.closeSubpath()

        return path
    }
}
