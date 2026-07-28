import SwiftUI

/// Toy 8-bar rainbow xylophone, C5..C6 (xylo_1 low .. xylo_8 high).
/// Landscape: vertical bars in a row, longest (lowest) on the left.
/// Portrait: horizontal bars stacked, longest at the bottom.
/// Multitouch with glissando (drag a finger across the bars), plus
/// follow-the-glow song mode: the next note's bar pulses gold; hitting
/// it advances the song, anything else just plays (no fail state).
struct XylophoneView: View {
    enum Song: String, CaseIterable {
        case twinkle = "Twinkle"
        case mary = "Mary"

        /// Scale degrees 1..8 into the bar array.
        var sequence: [Int] {
            switch self {
            case .twinkle:
                return [1,1,5,5,6,6,5, 4,4,3,3,2,2,1, 5,5,4,4,3,3,2, 5,5,4,4,3,3,2,
                        1,1,5,5,6,6,5, 4,4,3,3,2,2,1]
            case .mary:
                return [3,2,1,2,3,3,3, 2,2,2, 3,5,5, 3,2,1,2,3,3,3, 3,2,2,3,2,1]
            }
        }
    }

    @State private var strikes = [Int](repeating: 0, count: 8)
    @State private var lastStrikeTimes = [Date](repeating: .distantPast, count: 8)
    @State private var touchBars: [Int: Int] = [:]   // touch id -> bar index
    @State private var song: Song?
    @State private var songStep = 0
    @State private var celebrating = false

    var body: some View {
        GeometryReader { geo in
            let frames = Self.barFrames(in: geo.size)
            ZStack {
                background

                ForEach(0..<8, id: \.self) { index in
                    XyloBarView(color: RainbowPalette.colors[index],
                                strikes: strikes[index],
                                glowing: index == targetBar)
                        .frame(width: frames[index].width, height: frames[index].height)
                        .position(x: frames[index].midX, y: frames[index].midY)
                }

                MultiTouchView(
                    onBegan: { id, point in handleTouch(id: id, point: point, frames: frames, isStart: true) },
                    onMoved: { id, point in handleTouch(id: id, point: point, frames: frames, isStart: false) },
                    onEnded: { id in touchBars[id] = nil }
                )

                VStack {
                    HStack(spacing: 10) {
                        ForEach(Song.allCases, id: \.self) { candidate in
                            songButton(candidate)
                        }
                    }
                    .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.14, green: 0.17, blue: 0.23),
                     Color(red: 0.086, green: 0.11, blue: 0.15)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func songButton(_ candidate: Song) -> some View {
        Button {
            AudioEngine.shared.play("xylo_1")   // audible feedback + audio warmup
            if song == candidate {
                song = nil
            } else {
                song = candidate
            }
            songStep = 0
            celebrating = false
        } label: {
            Text("⭐ \(candidate.rawValue)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(song == candidate
                                 ? Color(red: 0.23, green: 0.17, blue: 0.03)
                                 : .white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(song == candidate
                                           ? Color(red: 0.96, green: 0.77, blue: 0.26)
                                           : Color.white.opacity(0.14)))
        }
    }

    private var targetBar: Int? {
        guard let song, !celebrating else { return nil }
        return song.sequence[songStep] - 1
    }

    /// Port of the web layout: landscape = vertical bars in a centered row
    /// (heights 78% -> 46%), portrait = stacked horizontal bars (widths
    /// 86% -> 52%, lowest at the bottom).
    static func barFrames(in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        let n = 8
        var frames: [CGRect] = []
        if w > h {
            let barW = w * 0.082
            let gap = w * 0.026
            let total = CGFloat(n) * barW + CGFloat(n - 1) * gap
            for i in 0..<n {
                let f = CGFloat(i) / CGFloat(n - 1)
                let barH = h * (0.78 - 0.32 * f)
                let x = (w - total) / 2 + CGFloat(i) * (barW + gap)
                frames.append(CGRect(x: x, y: (h - barH) / 2, width: barW, height: barH))
            }
        } else {
            let barH = h * 0.082
            let gap = h * 0.024
            let total = CGFloat(n) * barH + CGFloat(n - 1) * gap
            for i in 0..<n {
                let f = CGFloat(i) / CGFloat(n - 1)
                let barW = w * (0.86 - 0.34 * f)
                let y = (h - total) / 2 + CGFloat(n - 1 - i) * (barH + gap)
                frames.append(CGRect(x: (w - barW) / 2, y: y, width: barW, height: barH))
            }
        }
        return frames
    }

    private func handleTouch(id: Int, point: CGPoint, frames: [CGRect], isStart: Bool) {
        let hit = frames.firstIndex { $0.contains(point) }
        if let hit, isStart || touchBars[id] != hit {
            strike(hit)
        }
        touchBars[id] = hit ?? -1
    }

    private func strike(_ index: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastStrikeTimes[index]) > 0.06 else { return }
        lastStrikeTimes[index] = now
        barEffects(index)
        songNoteHit(index)
    }

    /// Sound + visual only — no song logic, so the celebration run can
    /// reuse it without advancing anything.
    private func barEffects(_ index: Int) {
        AudioEngine.shared.play("xylo_\(index + 1)")
        strikes[index] += 1
    }

    private func songNoteHit(_ index: Int) {
        guard let current = song, !celebrating, index == targetBar else { return }
        songStep += 1
        if songStep >= current.sequence.count {
            songStep = 0
            celebrating = true
            for k in 0..<8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13 * Double(k)) {
                    barEffects(k)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13 * 8 + 0.25) {
                celebrating = false
            }
        }
    }
}

/// One bar: rounded rainbow slab with two "nails", a strike bounce +
/// white flash, and a pulsing gold glow when it's the song's next note.
struct XyloBarView: View {
    let color: Color
    let strikes: Int
    let glowing: Bool

    @State private var pressed = false
    @State private var flash = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let vertical = h >= w
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .opacity(flash ? 0.55 : 0)
                    )
                ForEach(0..<2, id: \.self) { nail in
                    Circle()
                        .fill(Color(white: 0.94))
                        .frame(width: 12, height: 12)
                        .position(
                            x: vertical ? w / 2 : (nail == 0 ? w * 0.09 : w * 0.91),
                            y: vertical ? (nail == 0 ? h * 0.09 : h * 0.91) : h / 2
                        )
                }
            }
        }
        .scaleEffect(pressed ? 0.955 : 1)
        .shadow(color: .black.opacity(0.45), radius: 7, y: 5)
        .overlay {
            // A separate view whose repeat-forever animation lives and
            // dies with it: inserting/removing it on glow changes avoids
            // the lingering-animation flicker a modifier-based pulse gets
            // when sibling bars re-render (e.g. the celebration run).
            if glowing {
                GlowHalo()
            }
        }
        .onChange(of: strikes) { _ in
            pressed = true
            flash = true
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                pressed = false
            }
            withAnimation(.easeOut(duration: 0.28)) {
                flash = false
            }
        }
    }
}

/// Pulsing gold outline marking the song's next bar.
struct GlowHalo: View {
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(red: 1, green: 0.88, blue: 0.47), lineWidth: 4)
            .shadow(color: Color(red: 1, green: 0.88, blue: 0.47).opacity(0.9),
                    radius: bright ? 18 : 8)
            .opacity(bright ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}
