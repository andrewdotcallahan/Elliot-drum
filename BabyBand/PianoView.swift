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
            let vertical = Self.usesVerticalKeys(geo.size)
            let frames = Self.keyFrames(in: geo.size)
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.14, blue: 0.19),
                             Color(red: 0.082, green: 0.063, blue: 0.098)],
                    startPoint: .top, endPoint: .bottom
                )

                ForEach(0..<8, id: \.self) { index in
                    PianoKeyView(strip: RainbowPalette.colors[index],
                                 strikes: strikes[index],
                                 verticalKey: vertical)
                        .frame(width: frames[index].width, height: frames[index].height)
                        .position(x: frames[index].midX, y: frames[index].midY)
                }

                MultiTouchView(
                    onBegan: { id, point in handleTouch(id: id, point: point, frames: frames, vertical: vertical, isStart: true) },
                    onMoved: { id, point in handleTouch(id: id, point: point, frames: frames, vertical: vertical, isStart: false) },
                    onEnded: { id in touchKeys[id] = nil }
                )
            }
        }
        .ignoresSafeArea()
    }

    /// Classic vertical keys need enough width for 8 toddler-sized keys;
    /// a phone in portrait doesn't have it, so keys become stacked
    /// horizontal slabs there (lowest note at the bottom), like the
    /// xylophone's portrait arrangement.
    static func usesVerticalKeys(_ size: CGSize) -> Bool {
        size.width > size.height || size.width >= 500
    }

    static func keyFrames(in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        let n = 8
        if usesVerticalKeys(size) {
            let gap = max(4, w * 0.006)
            let total = w * 0.96
            let keyW = (total - CGFloat(n - 1) * gap) / CGFloat(n)
            let keyH = h * 0.74
            let x0 = (w - total) / 2
            return (0..<n).map { i in
                CGRect(x: x0 + CGFloat(i) * (keyW + gap), y: h - keyH, width: keyW, height: keyH)
            }
        } else {
            let gap = max(4, h * 0.008)
            let total = h * 0.88
            let keyH = (total - CGFloat(n - 1) * gap) / CGFloat(n)
            let keyW = w * 0.92
            let y0 = (h - total) / 2
            return (0..<n).map { i in
                CGRect(x: (w - keyW) / 2,
                       y: y0 + CGFloat(n - 1 - i) * (keyH + gap),   // low C at the bottom
                       width: keyW, height: keyH)
            }
        }
    }

    private func handleTouch(id: Int, point: CGPoint, frames: [CGRect], vertical: Bool, isStart: Bool) {
        // Inside the keyboard region, land between-the-gaps touches on the
        // nearest key (toddler fingers shouldn't fall through).
        var hit: Int?
        if vertical {
            if point.y >= frames[0].minY {
                hit = frames.firstIndex { point.x >= $0.minX - 3 && point.x <= $0.maxX + 3 }
            }
        } else {
            hit = frames.firstIndex { point.y >= $0.minY - 3 && point.y <= $0.maxY + 3 }
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
    let verticalKey: Bool

    @State private var pressed = false
    @State private var flash = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                keyShape
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
                    .frame(width: verticalKey ? w * 0.84 : w * 0.13,
                           height: verticalKey ? h * 0.14 : h * 0.72)
                    .position(x: verticalKey ? w / 2 : w * 0.91,
                              y: verticalKey ? h * 0.88 : h / 2)
            }
        }
        .offset(y: pressed && verticalKey ? 6 : 0)
        .scaleEffect(pressed && !verticalKey ? 0.97 : 1)
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

    private var keyShape: AnyShape {
        verticalKey
            ? AnyShape(UnevenRoundedRectangleCompat(bottomRadius: 14))
            : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
