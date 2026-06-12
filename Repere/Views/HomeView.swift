import SwiftUI

// MARK: - Home View (Main Entry Screen)
struct HomeView: View {
    @State private var displayName: String = ""
    @State private var groupCode: String = ""
    @State private var showRadar = false
    @State private var isCreating = false
    @State private var isJoining = false
    @State private var generatedCode: String = ""
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color(hex: "0F0C29"),
                    Color(hex: "302B63"),
                    Color(hex: "24243E")
                ],
                startPoint: animateGradient ? .topLeading : .bottomLeading,
                endPoint: animateGradient ? .bottomTrailing : .topTrailing
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    animateGradient.toggle()
                }
            }

            // Floating background orbs
            FloatingOrbsView()

            VStack(spacing: 30) {
                Spacer()

                // Logo section
                logoSection

                Spacer()

                // Pseudo input
                pseudoInput

                // Action buttons
                actionButtons

                Spacer().frame(height: 40)
            }
        }
        .sheet(isPresented: $isCreating) {
            CreateGroupSheet(displayName: displayName) { code in
                generatedCode = code
                groupCode = ""
                showRadar = true
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isJoining) {
            JoinGroupSheet(displayName: displayName) { code in
                // Clear any previously generated code, otherwise the radar
                // would reopen as host with the old code instead of joining
                generatedCode = ""
                groupCode = code
                showRadar = true
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showRadar) {
            RadarView(
                displayName: displayName,
                groupCode: generatedCode.isEmpty ? groupCode : generatedCode,
                isHost: !generatedCode.isEmpty
            )
        }
    }

    // MARK: - Logo
    private var logoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "6C63FF").opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "6C63FF"), Color(hex: "E942F5")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .rotationEffect(.degrees(-15))
            }

            Text("Repère")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Retrouve tes potes. Sans réseau.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Pseudo Input
    private var pseudoInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ton pseudo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            TextField("", text: $displayName,
                      prompt: Text("Ex: Alex").foregroundColor(.white.opacity(0.3)))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal)
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 14) {
            // Create group
            Button {
                guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                isCreating = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Créer un groupe")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "6C63FF"), Color(hex: "E942F5")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color(hex: "6C63FF").opacity(0.4), radius: 15, y: 5)
            }
            .opacity(displayName.isEmpty ? 0.5 : 1)
            .disabled(displayName.isEmpty)

            // Join group
            Button {
                guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                isJoining = true
            } label: {
                HStack {
                    Image(systemName: "person.2.fill")
                    Text("Rejoindre un groupe")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .foregroundColor(.white)
            }
            .opacity(displayName.isEmpty ? 0.5 : 1)
            .disabled(displayName.isEmpty)
        }
        .padding(.horizontal)
    }
}

// MARK: - Create Group Sheet
struct CreateGroupSheet: View {
    let displayName: String
    let onStart: (String) -> Void
    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "1A1A2E").ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Ton code de groupe")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Partage ce code à tes potes !")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                // Code display
                HStack(spacing: 12) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                        Text(String(char))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 70)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "6C63FF").opacity(0.5), lineWidth: 2)
                                    )
                            )
                    }
                }
                .onAppear {
                    code = String(format: "%04d", Int.random(in: 0...9999))
                }

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onStart(code)
                    }
                } label: {
                    Text("C'est parti ! 🚀")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "6C63FF"), Color(hex: "E942F5")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

// MARK: - Join Group Sheet
struct JoinGroupSheet: View {
    let displayName: String
    let onJoin: (String) -> Void
    @State private var codeText: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "1A1A2E").ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Code du groupe")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Demande le code à ton pote")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                // Simple 4-digit code input
                TextField("", text: $codeText,
                          prompt: Text("0000").foregroundColor(.white.opacity(0.2)))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
                    .onChange(of: codeText) { newValue in
                        // Limit to 4 digits
                        if newValue.count > 4 {
                            codeText = String(newValue.prefix(4))
                        }
                        // Only allow digits
                        codeText = codeText.filter { $0.isNumber }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "6C63FF").opacity(0.3), lineWidth: 2)
                            )
                    )
                    .padding(.horizontal, 60)
                    .onAppear { isFocused = true }

                // Letter spacing indicator
                Text("\(codeText.count)/4 chiffres")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))

                Button {
                    guard codeText.count == 4 else { return }
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onJoin(codeText)
                    }
                } label: {
                    Text("Rejoindre 🎯")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "6C63FF"), Color(hex: "E942F5")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
                .opacity(codeText.count == 4 ? 1 : 0.5)
                .disabled(codeText.count != 4)
            }
            .padding()
        }
    }
}

// MARK: - Floating Orbs Background
struct FloatingOrbsView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "6C63FF").opacity(0.15))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: animate ? 50 : -50, y: animate ? -30 : 30)

            Circle()
                .fill(Color(hex: "E942F5").opacity(0.1))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: animate ? -60 : 60, y: animate ? 50 : -50)

            Circle()
                .fill(Color(hex: "42E9C2").opacity(0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: animate ? 30 : -30, y: animate ? 80 : -20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
