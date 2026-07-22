import SwiftUI

struct GuitarStringSpec: Identifiable {
    let id: Int          // 0 = lowest pitch (bottom of screen, thickest) ... 5 = highest (top, thinnest)
    let sound: String
    let thickness: CGFloat
}

/// Strings sit between 16% and 86% of the screen height; string 0 (lowest
/// pitch, thickest) at the bottom, string 5 at the top. Shared by the
/// strings and the bridge-pin drawing so they always line up.
private func guitarStringY(_ index: Int, height: CGFloat) -> CGFloat {
    let top = height * 0.16
    let bottom = height * 0.86
    let step = (bottom - top) / 5
    return bottom - CGFloat(index) * step
}

struct GuitarView: View {
    private static let strings: [GuitarStringSpec] = [
        GuitarStringSpec(id: 0, sound: "guitar_s1", thickness: 6.0),
        GuitarStringSpec(id: 1, sound: "guitar_s2", thickness: 5.3),
        GuitarStringSpec(id: 2, sound: "guitar_s3", thickness: 4.6),
        GuitarStringSpec(id: 3, sound: "guitar_s4", thickness: 3.9),
        GuitarStringSpec(id: 4, sound: "guitar_s5", thickness: 3.2),
        GuitarStringSpec(id: 5, sound: "guitar_s6", thickness: 2.5)
    ]

    @State private var pluckCounts = [Int](repeating: 0, count: 6)
    @State private var lastPluckTimes = [Date](repeating: .distantPast, count: 6)
    @State private var previousY: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GuitarBodyBackground(size: geo.size)

                ForEach(Self.strings) { string in
                    GuitarStringView(spec: string, pluckCount: pluckCounts[string.id], width: geo.size.width)
                        .position(x: geo.size.width / 2,
                                  y: guitarStringY(string.id, height: geo.size.height))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleTouch(y: value.location.y, height: geo.size.height)
                    }
                    .onEnded { _ in
                        previousY = nil
                    }
            )
        }
        .ignoresSafeArea()
    }

    private func handleTouch(y: CGFloat, height: CGFloat) {
        let step = (height * 0.70) / 5
        for string in Self.strings {
            let sy = guitarStringY(string.id, height: height)
            let hit: Bool
            if let prev = previousY {
                // Pluck whenever the finger crosses the string's line.
                hit = (prev < sy && y >= sy) || (prev > sy && y <= sy)
            } else {
                // First touch: pluck the string whose band was tapped.
                hit = abs(y - sy) < step * 0.45
            }
            if hit {
                pluck(string)
            }
        }
        previousY = y
    }

    private func pluck(_ string: GuitarStringSpec) {
        let now = Date()
        // Per-string debounce so a slow finger doesn't machine-gun one string.
        guard now.timeIntervalSince(lastPluckTimes[string.id]) > 0.08 else { return }
        lastPluckTimes[string.id] = now
        pluckCounts[string.id] += 1
        AudioEngine.shared.play(string.sound)
    }
}

/// The guitar top: warm layered wood, subtle grain streaks, an off-center
/// soundhole with a decorative rosette, and a bridge with pins under the
/// strings. Pure gradients and shapes, no image assets.
struct GuitarBodyBackground: View {
    let size: CGSize

    /// (y fraction, streak height in points, opacity)
    private static let grainStreaks: [(y: CGFloat, height: CGFloat, opacity: Double)] = [
        (0.05, 2.0, 0.12), (0.13, 3.0, 0.09), (0.24, 2.0, 0.13),
        (0.35, 2.5, 0.09), (0.48, 2.0, 0.11), (0.63, 3.0, 0.09),
        (0.77, 2.0, 0.12), (0.92, 2.5, 0.10)
    ]

    var body: some View {
        let w = size.width
        let h = size.height
        let holeCenter = CGPoint(x: w * 0.40, y: h * 0.51)
        let holeRadius = min(w, h) * (w > h ? 0.185 : 0.22)
        let bridgeX = w * 0.80
        let bridgeWidth = min(w, h) * 0.075
        let bridgeTop = h * 0.125
        let bridgeHeight = h * 0.77

        ZStack {
            // Warm layered wood.
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.35, blue: 0.16),
                    Color(red: 0.68, green: 0.45, blue: 0.22),
                    Color(red: 0.48, green: 0.29, blue: 0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.white.opacity(0.0), location: 0.0),
                    Gradient.Stop(color: Color.white.opacity(0.07), location: 0.35),
                    Gradient.Stop(color: Color.white.opacity(0.0), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Grain streaks: thin, dark, quiet — the strings stay the stars.
            ForEach(0..<Self.grainStreaks.count, id: \.self) { index in
                let streak = Self.grainStreaks[index]
                Capsule()
                    .fill(Color(red: 0.25, green: 0.13, blue: 0.05).opacity(streak.opacity))
                    .frame(width: w, height: streak.height)
                    .position(x: w / 2, y: streak.y * h)
            }

            // Rosette: dark band with a dashed gold mosaic, thin gold rings.
            Circle()
                .stroke(Color(red: 0.20, green: 0.10, blue: 0.04), lineWidth: holeRadius * 0.18)
                .frame(width: holeRadius * 2.36, height: holeRadius * 2.36)
                .position(holeCenter)
            Circle()
                .stroke(
                    Color(red: 0.85, green: 0.68, blue: 0.35).opacity(0.8),
                    style: StrokeStyle(lineWidth: holeRadius * 0.06,
                                       dash: [holeRadius * 0.07, holeRadius * 0.05])
                )
                .frame(width: holeRadius * 2.36, height: holeRadius * 2.36)
                .position(holeCenter)
            Circle()
                .stroke(Color(red: 0.85, green: 0.68, blue: 0.35), lineWidth: 2)
                .frame(width: holeRadius * 2.12, height: holeRadius * 2.12)
                .position(holeCenter)
            Circle()
                .stroke(Color(red: 0.85, green: 0.68, blue: 0.35), lineWidth: 2)
                .frame(width: holeRadius * 2.60, height: holeRadius * 2.60)
                .position(holeCenter)

            // Soundhole.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.10, green: 0.06, blue: 0.03),
                            Color(red: 0.03, green: 0.02, blue: 0.01)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: holeRadius
                    )
                )
                .frame(width: holeRadius * 2, height: holeRadius * 2)
                .position(holeCenter)
            Circle()
                .stroke(Color.black.opacity(0.6), lineWidth: 4)
                .frame(width: holeRadius * 2, height: holeRadius * 2)
                .position(holeCenter)

            // Bridge bar (perpendicular to the strings) with saddle and pins.
            RoundedRectangle(cornerRadius: bridgeWidth * 0.35, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.12, blue: 0.05),
                            Color(red: 0.14, green: 0.07, blue: 0.03)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: bridgeWidth, height: bridgeHeight)
                .position(x: bridgeX, y: bridgeTop + bridgeHeight / 2)
                .shadow(color: .black.opacity(0.4), radius: 5, x: 3, y: 3)
            Capsule()
                .fill(Color(white: 0.92))
                .frame(width: bridgeWidth * 0.14, height: bridgeHeight * 0.88)
                .position(x: bridgeX - bridgeWidth * 0.18, y: bridgeTop + bridgeHeight / 2)
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(Color(white: 0.90))
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: bridgeWidth * 0.24, height: bridgeWidth * 0.24)
                    .position(x: bridgeX + bridgeWidth * 0.22,
                              y: guitarStringY(index, height: h))
            }
        }
        .allowsHitTesting(false)
    }
}

/// One string. On pluck it vibrates as a decaying sine wave for ~0.5s
/// (TimelineView + Canvas, paused when idle so it costs nothing at rest)
/// and glows softly. Hit testing stays with the parent strum gesture.
struct GuitarStringView: View {
    let spec: GuitarStringSpec
    let pluckCount: Int
    let width: CGFloat

    @State private var isVibrating = false
    @State private var pluckDate = Date.distantPast
    @State private var glow: Double = 0
    @State private var stopTask: DispatchWorkItem?

    private let vibrationDuration: TimeInterval = 0.5
    private let maxAmplitude: CGFloat = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isVibrating)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(pluckDate)
            Canvas { context, canvasSize in
                let midY = canvasSize.height / 2
                let progress = elapsed / vibrationDuration
                var amplitude: CGFloat = 0
                if isVibrating && progress >= 0 && progress < 1 {
                    amplitude = maxAmplitude * CGFloat(1 - progress)
                }

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))
                if amplitude > 0.1 {
                    let waves = 3.0
                    let phaseSpeed = elapsed * 55
                    var x: CGFloat = 0
                    while x <= canvasSize.width {
                        let fraction = Double(x) / Double(canvasSize.width)
                        let envelope = sin(fraction * .pi)   // pinned at both ends
                        let wave = sin(fraction * waves * 2 * .pi + phaseSpeed)
                        let y = midY + amplitude * CGFloat(envelope * wave)
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 6
                    }
                    path.addLine(to: CGPoint(x: canvasSize.width, y: midY))
                } else {
                    path.addLine(to: CGPoint(x: canvasSize.width, y: midY))
                }

                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(white: 0.60), Color(white: 0.98), Color(white: 0.52)]),
                    startPoint: CGPoint(x: 0, y: midY - spec.thickness),
                    endPoint: CGPoint(x: 0, y: midY + spec.thickness)
                )
                context.stroke(path, with: shading,
                               style: StrokeStyle(lineWidth: spec.thickness, lineCap: .round))
            }
        }
        .frame(width: width, height: maxAmplitude * 2 + spec.thickness + 4)
        .shadow(color: Color.black.opacity(0.35), radius: 2, y: 2)
        .shadow(color: Color(red: 1.0, green: 0.9, blue: 0.5).opacity(glow * 0.8), radius: 10)
        .allowsHitTesting(false)
        .onChange(of: pluckCount) { _ in
            startVibration()
        }
        .onDisappear {
            stopTask?.cancel()
        }
    }

    private func startVibration() {
        pluckDate = Date()
        isVibrating = true
        glow = 1
        withAnimation(.easeOut(duration: 0.5)) {
            glow = 0
        }
        stopTask?.cancel()
        let task = DispatchWorkItem {
            isVibrating = false
        }
        stopTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + vibrationDuration + 0.05, execute: task)
    }
}
