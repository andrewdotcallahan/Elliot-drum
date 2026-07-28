import SwiftUI

/// Toy grand: 8 big white keys (C4..C5, piano_1..piano_8) with rainbow
/// strips, anchored to the bottom edge. Multitouch chords and glissando
/// drags, same interaction model as the xylophone.
struct PianoView: View {
    @State private var strikes = [Int](repeating: 0, count: 8)
    @State private var lastStrikeTimes = [Date](repeating: .distantPast, count: 8)
    @State private var touchKeys: [Int: Int] = [:]

    var body: some View {
        GeometryReader { geo in
            let frames = Self.keyFrames(in: geo.size)
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.14, blue: 0.19),
                             Color(red: 0.082, green: 0.063, blue: 0.098)],
                    startPoint: .top, endPoint: .bottom
                )

                ForEach(0..<8, id: \.self) { index in
                    PianoKeyView(strip: RainbowPalette.colors[index], strikes: strikes[index])
                        .frame(width: frames[index].width, height: frames[index].height)
                        .position(x: frames[index].midX, y: frames[index].midY)
                }

                MultiTouchView(
                    onBegan: { id, point in handleTouch(id: id, point: point, frames: frames, isStart: true) },
                    onMoved: { id, point in handleTouch(id: id, point: point, frames: frames, isStart: false) },
                    onEnded: { id in touchKeys[id] = nil }
                )
            }
        }
        .ignoresSafeArea()
    }

    static func keyFrames(in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        let n = 8
        let gap = max(4, w * 0.006)
        let total = w * 0.96
        let keyW = (total - CGFloat(n - 1) * gap) / CGFloat(n)
        let keyH = h * 0.74
        let x0 = (w - total) / 2
        return (0..<n).map { i in
            CGRect(x: x0 + CGFloat(i) * (keyW + gap), y: h - keyH, width: keyW, height: keyH)
        }
    }

    private func handleTouch(id: Int, point: CGPoint, frames: [CGRect], isStart: Bool) {
        // Below the key tops, any x position maps to a key (toddler fingers
        // shouldn't fall through the gaps).
        var hit: Int?
        if point.y >= frames[0].minY {
            hit = frames.firstIndex { point.x >= $0.minX - 3 && point.x <= $0.maxX + 3 }
        }
        if let hit, isStart || touchKeys[id] != hit {
            strike(hit)
        }
        touchKeys[id] = hit ?? -1
    }

    private func strike(_ index: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastStrikeTimes[index]) > 0.06 else { return }
        lastStrikeTimes[index] = now
        AudioEngine.shared.play("piano_\(index + 1)")
        strikes[index] += 1
    }
}

struct PianoKeyView: View {
    let strip: Color
    let strikes: Int

    @State private var pressed = false
    @State private var flash = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                UnevenRoundedRectangleCompat(bottomRadius: 14)
                    .fill(LinearGradient(
                        colors: [Color.white,
                                 Color(red: 0.95, green: 0.94, blue: 0.91),
                                 Color(red: 0.87, green: 0.85, blue: 0.80)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 6)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(strip)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                            .opacity(flash ? 0.6 : 0)
                    )
                    .frame(width: w * 0.84, height: h * 0.14)
                    .position(x: w / 2, y: h * 0.88)
            }
        }
        .offset(y: pressed ? 6 : 0)
        .onChange(of: strikes) { _ in
            pressed = true
            flash = true
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pressed = false
            }
            withAnimation(.easeOut(duration: 0.26)) {
                flash = false
            }
        }
    }
}

/// Rectangle with rounded bottom corners only (piano keys). iOS 16 has no
/// UnevenRoundedRectangle (that's iOS 16.4+/17 for the shape init), so
/// draw it with a Path.
struct UnevenRoundedRectangleCompat: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.width / 2, rect.height / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
