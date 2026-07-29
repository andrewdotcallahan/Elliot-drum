import SwiftUI

/// Steel tongue drum, top-down: a big teal steel disc with 8 tongue pads
/// arranged radially (lowest note at the bottom, ascending clockwise),
/// tuned to C major pentatonic so any flurry of taps sounds lovely.
/// Multitouch, with glissando — sweeping a finger around the drum plays
/// the tongues as it crosses them.
struct TongueDrumView: View {
    @State private var strikes = [Int](repeating: 0, count: 8)
    @State private var lastStrikeTimes = [Date](repeating: .distantPast, count: 8)
    @State private var touchTongues: [Int: Int] = [:]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let radius = min(w, h) * 0.42

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.137, green: 0.137, blue: 0.22),
                             Color(red: 0.063, green: 0.063, blue: 0.094)],
                    startPoint: .top, endPoint: .bottom
                )

                drumBody(radius: radius)
                    .position(center)

                ForEach(0..<8, id: \.self) { index in
                    let geometry = Self.tongueGeometry(index: index, radius: radius, center: center)
                    TongueView(strikes: strikes[index],
                               width: geometry.width, length: geometry.length)
                        .rotationEffect(.radians(geometry.angle + .pi / 2))
                        .position(geometry.position)
                }

                Circle()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 2))
                    .frame(width: radius * 0.16, height: radius * 0.16)
                    .position(center)

                MultiTouchView(
                    onBegan: { id, point in handleTouch(id: id, point: point, center: center, radius: radius, isStart: true) },
                    onMoved: { id, point in handleTouch(id: id, point: point, center: center, radius: radius, isStart: false) },
                    onEnded: { id in touchTongues[id] = nil }
                )
            }
        }
        .ignoresSafeArea()
    }

    private func drumBody(radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.24, green: 0.50, blue: 0.52),
                                 Color(red: 0.16, green: 0.37, blue: 0.40),
                                 Color(red: 0.09, green: 0.24, blue: 0.27)],
                        center: UnitPoint(x: 0.42, y: 0.36),
                        startRadius: 0,
                        endRadius: radius * 1.25
                    )
                )
            Circle()
                .strokeBorder(Color(red: 0.05, green: 0.14, blue: 0.16),
                              lineWidth: max(5, radius * 0.035))
        }
        .frame(width: radius * 2, height: radius * 2)
        .shadow(color: .black.opacity(0.6), radius: radius * 0.09, y: radius * 0.06)
    }

    /// Tongue i sits at angle 90° + i*45° (screen coordinates, so index 0
    /// is at the bottom), long axis pointing at the center. Lower notes
    /// get longer, wider tongues.
    static func tongueGeometry(index: Int, radius: CGFloat, center: CGPoint)
        -> (position: CGPoint, angle: CGFloat, width: CGFloat, length: CGFloat) {
        let f = CGFloat(index) / 7
        let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / 4
        let length = radius * (0.46 - 0.16 * f)
        let width = radius * (0.17 - 0.05 * f)
        let ringRadius = radius * 0.58
        let position = CGPoint(x: center.x + cos(angle) * ringRadius,
                               y: center.y + sin(angle) * ringRadius)
        return (position, angle, width, length)
    }

    private func handleTouch(id: Int, point: CGPoint, center: CGPoint,
                             radius: CGFloat, isStart: Bool) {
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        var hit: Int?
        if distance > radius * 0.14 && distance < radius * 1.05 {
            let angle = atan2(dy, dx)
            var sector = Int((angle - .pi / 2) / (.pi / 4) + 0.5)
            sector = ((sector % 8) + 8) % 8
            hit = sector
        }
        if let hit, isStart || touchTongues[id] != hit {
            strike(hit)
        }
        touchTongues[id] = hit ?? -1
    }

    private func strike(_ index: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastStrikeTimes[index]) > 0.06 else { return }
        lastStrikeTimes[index] = now
        AudioEngine.shared.play("tongue_\(index + 1)")
        strikes[index] += 1
    }
}

/// One tongue pad: a raised steel capsule with a slot outline and a
/// dimple. On strike it flashes and rings outward.
struct TongueView: View {
    let strikes: Int
    let width: CGFloat
    let length: CGFloat

    @State private var flash = false
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.33, green: 0.62, blue: 0.64),
                                 Color(red: 0.20, green: 0.44, blue: 0.47)],
                        startPoint: .top, endPoint: .bottom))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(red: 0.04, green: 0.12, blue: 0.14),
                                lineWidth: max(2.5, width * 0.09))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .opacity(flash ? 0.45 : 0)
                )
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: width * 0.36, height: width * 0.36)
                .offset(y: length * 0.26)

            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
        }
        .frame(width: width, height: length)
        .onChange(of: strikes) { _ in
            flash = true
            ringScale = 1
            ringOpacity = 0.8
            withAnimation(.easeOut(duration: 0.5)) {
                flash = false
                ringScale = 1.5
                ringOpacity = 0
            }
        }
    }
}
