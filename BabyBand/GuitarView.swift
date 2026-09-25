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

/// Both guitars play the same way (open G, strum anywhere); they differ
/// only in sound set and body artwork.
enum GuitarStyle {
    case acoustic
    case electric

    /// Sound file prefix: guitar_s1...s6 or electric_s1...s6.
    var soundPrefix: String {
        switch self {
        case .acoustic: return "guitar_s"
        case .electric: return "electric_s"
        }
    }
}

struct GuitarView: View {
    var style: GuitarStyle = .acoustic

    private static let thicknesses: [CGFloat] = [6.0, 5.3, 4.6, 3.9, 3.2, 2.5]

    private var strings: [GuitarStringSpec] {
        Self.thicknesses.enumerated().map { index, thickness in
            GuitarStringSpec(id: index, sound: "\(style.soundPrefix)\(index + 1)", thickness: thickness)
        }
    }

    @State private var pluckCounts = [Int](repeating: 0, count: 6)
    @State private var lastPluckTimes = [Date](repeating: .distantPast, count: 6)
    @State private var previousY: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch style {
                case .acoustic: GuitarBodyBackground(size: geo.size)
                case .electric: ElectricGuitarBodyBackground(size: geo.size)
                }

                ForEach(strings) { string in
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
        for string in strings {
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

/// The electric guitar top: a glossy cherry-sunburst finish, a cream
/// pickguard, two chrome humbuckers under the strings, a tune-o-matic
/// bridge with saddles, a stop tailpiece, and volume/tone knobs. Same
/// string geometry as the acoustic, so the strings sit over the
/// pickups' pole pieces.
struct ElectricGuitarBodyBackground: View {
    let size: CGSize

    var body: some View {
        let w = size.width
        let h = size.height
        let unit = min(w, h)
        let stringTop = guitarStringY(5, height: h)
        let stringBottom = guitarStringY(0, height: h)
        let spanHeight = stringBottom - stringTop
        let pickupWidth = unit * 0.13
        let pickupHeight = spanHeight + unit * 0.12
        let bridgeX = w * 0.78
        let tailX = w * 0.89

        ZStack {
            // Cherry sunburst: bright center fading to deep burgundy edges.
            RadialGradient(
                colors: [
                    Color(red: 0.93, green: 0.36, blue: 0.16),
                    Color(red: 0.74, green: 0.10, blue: 0.10),
                    Color(red: 0.30, green: 0.03, blue: 0.05)
                ],
                center: UnitPoint(x: 0.55, y: 0.5),
                startRadius: 0,
                endRadius: max(w, h) * 0.62
            )
            // Glossy clear-coat sheen.
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.white.opacity(0.0), location: 0.0),
                    Gradient.Stop(color: Color.white.opacity(0.16), location: 0.22),
                    Gradient.Stop(color: Color.white.opacity(0.0), location: 0.45),
                    Gradient.Stop(color: Color.white.opacity(0.0), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Cream pickguard behind the pickups.
            RoundedRectangle(cornerRadius: unit * 0.08, style: .continuous)
                .fill(Color(red: 0.96, green: 0.92, blue: 0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: unit * 0.08, style: .continuous)
                        .stroke(Color.black.opacity(0.35), lineWidth: 2)
                )
                .frame(width: w * 0.40, height: pickupHeight + unit * 0.10)
                .position(x: w * 0.47, y: (stringTop + stringBottom) / 2)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 3, y: 4)

            // Neck and bridge humbuckers.
            ForEach([w * 0.38, w * 0.58], id: \.self) { x in
                Humbucker(width: pickupWidth, height: pickupHeight,
                          centerY: (stringTop + stringBottom) / 2, screenHeight: h)
                    .position(x: x, y: (stringTop + stringBottom) / 2)
            }

            // Tune-o-matic bridge: a chrome bar with one saddle per string.
            RoundedRectangle(cornerRadius: unit * 0.015, style: .continuous)
                .fill(Self.chrome)
                .frame(width: unit * 0.05, height: spanHeight + unit * 0.10)
                .position(x: bridgeX, y: (stringTop + stringBottom) / 2)
                .shadow(color: .black.opacity(0.45), radius: 4, x: 2, y: 3)
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.55))
                    .frame(width: unit * 0.03, height: unit * 0.018)
                    .position(x: bridgeX, y: guitarStringY(index, height: h))
            }

            // Stop tailpiece where the strings anchor.
            Capsule()
                .fill(Self.chrome)
                .frame(width: unit * 0.06, height: spanHeight + unit * 0.14)
                .position(x: tailX, y: (stringTop + stringBottom) / 2)
                .shadow(color: .black.opacity(0.45), radius: 4, x: 2, y: 3)

            // Volume and tone knobs in the lower corner, clear of the strings.
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.98, green: 0.85, blue: 0.45),
                                     Color(red: 0.62, green: 0.44, blue: 0.12)],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: unit * 0.03)
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .frame(width: unit * 0.055, height: unit * 0.055)
                    .position(x: w * (0.70 + CGFloat(index) * 0.07),
                              y: min(h - unit * 0.035, stringBottom + (h - stringBottom) * 0.55))
            }
        }
        .allowsHitTesting(false)
    }

    static let chrome = LinearGradient(
        colors: [Color(white: 0.95), Color(white: 0.62), Color(white: 0.88), Color(white: 0.50)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// One humbucker: a black bobbin pair in a chrome ring, with a pole
/// piece under each string.
private struct Humbucker: View {
    let width: CGFloat
    let height: CGFloat
    /// Where the pickup is centered on screen, and the screen height, for
    /// lining the pole pieces up with the strings.
    let centerY: CGFloat
    let screenHeight: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .fill(ElectricGuitarBodyBackground.chrome)
            HStack(spacing: width * 0.06) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                        .fill(Color(white: 0.10))
                }
            }
            .padding(width * 0.10)
            // Pole pieces, in the pickup's own coordinates.
            GeometryReader { geo in
                let originY = centerY - height / 2
                ForEach(0..<6, id: \.self) { index in
                    ForEach(0..<2, id: \.self) { column in
                        Circle()
                            .fill(Color(white: 0.75))
                            .frame(width: width * 0.14, height: width * 0.14)
                            .position(x: geo.size.width * (column == 0 ? 0.30 : 0.70),
                                      y: guitarStringY(index, height: screenHeight) - originY)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.4), radius: 4, x: 2, y: 3)
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
