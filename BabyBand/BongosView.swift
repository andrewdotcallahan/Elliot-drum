import SwiftUI

/// Three hand drums, top-down view, sized for baby palms: low conga,
/// mid conga, high bongo. Touch-down to hit, like the drum kit; each
/// drum owns its gesture so several can be slapped at once.
struct BongosView: View {
    private static let sounds = ["conga_lo", "conga_mid", "bongo_hi"]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let spots: [(CGFloat, CGFloat, CGFloat)] = w > h
                ? [(0.22 * w, 0.55 * h, 0.55 * h),
                   (0.52 * w, 0.50 * h, 0.46 * h),
                   (0.79 * w, 0.45 * h, 0.36 * h)]
                : [(0.50 * w, 0.76 * h, 0.56 * w),
                   (0.50 * w, 0.47 * h, 0.47 * w),
                   (0.50 * w, 0.22 * h, 0.37 * w)]

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.20, green: 0.137, blue: 0.11),
                             Color(red: 0.098, green: 0.063, blue: 0.035)],
                    startPoint: .top, endPoint: .bottom
                )

                ForEach(0..<3, id: \.self) { index in
                    HandDrumView(sound: Self.sounds[index], diameter: spots[index].2)
                        .position(x: spots[index].0, y: spots[index].1)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct HandDrumView: View {
    let sound: String
    let diameter: CGFloat

    @State private var isPressed = false
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.96, green: 0.90, blue: 0.78),
                                 Color(red: 0.90, green: 0.82, blue: 0.66),
                                 Color(red: 0.80, green: 0.69, blue: 0.52)],
                        center: UnitPoint(x: 0.42, y: 0.38),
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        Color(red: 0.43, green: 0.27, blue: 0.13),
                        lineWidth: max(6, diameter * 0.045))
                )
                .shadow(color: .black.opacity(0.55), radius: 13, y: 10)

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.spring(response: 0.16, dampingFraction: 0.5), value: isPressed)
        .contentShape(Circle().scale(1.15))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    AudioEngine.shared.play(sound)
                    ringScale = 1
                    ringOpacity = 0.8
                    withAnimation(.easeOut(duration: 0.35)) {
                        ringScale = 1.18
                        ringOpacity = 0
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
