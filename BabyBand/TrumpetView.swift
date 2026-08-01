import SwiftUI

/// Valve trumpet: touch anywhere to start the tone, slide along the horn
/// to step through a C major arpeggio (C4 E4 G4 C5) — higher toward the
/// bell, so any noodling stays consonant with the other instruments.
/// Monophonic like the real thing. The three valves animate each note's
/// fingering (fewer valves down = higher note) and the bell radiates
/// colored sound arcs while playing. Drawn in a Canvas that rotates for
/// portrait (bell points down).
struct TrumpetView: View {
    @State private var noteIndex: Int?   // nil = silent

    /// Which valves are down for each note, low to high. Purely visual,
    /// but it makes the pitch visible: the horn "opens up" as you rise.
    static let fingerings: [[Bool]] = [
        [true, true, true],     // C4
        [true, true, false],    // E4
        [true, false, false],   // G4
        [false, false, false]   // C5 (open)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    Self.draw(context: context, size: size, note: noteIndex)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let note = Self.note(at: value.location, in: geo.size)
                                if noteIndex == nil {
                                    AudioEngine.shared.trumpetStart(note: note)
                                } else if note != noteIndex {
                                    AudioEngine.shared.trumpetChange(to: note)
                                }
                                noteIndex = note
                            }
                            .onEnded { _ in
                                noteIndex = nil
                                AudioEngine.shared.trumpetStop()
                            }
                    )
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            AudioEngine.shared.trumpetStop()
        }
    }

    static func note(at point: CGPoint, in size: CGSize) -> Int {
        let long = max(size.width, size.height)
        let value = size.width > size.height ? point.x : point.y
        let pos = min(1, max(0, (value - long * 0.15) / (long * 0.70)))
        return min(fingerings.count - 1, Int(pos * Double(fingerings.count)))
    }

    // MARK: - Drawing

    static func draw(context: GraphicsContext, size: CGSize, note: Int?) {
        let w = size.width, h = size.height

        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(
                        Gradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.22),
                                          Color(red: 0.05, green: 0.07, blue: 0.13)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: h)))

        let landscape = w > h
        var body = context
        var W = w, H = h
        if !landscape {
            W = h; H = w
            body.translateBy(x: w, y: 0)
            body.rotate(by: .degrees(90))
        }

        let yc = H * 0.46
        let r = H * 0.032
        let lowY = yc + H * 0.17

        func brass(_ y: CGFloat, _ radius: CGFloat) -> GraphicsContext.Shading {
            .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.96, green: 0.85, blue: 0.55), location: 0),
                    .init(color: Color(red: 0.85, green: 0.64, blue: 0.25), location: 0.45),
                    .init(color: Color(red: 0.54, green: 0.39, blue: 0.13), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: y - radius),
                endPoint: CGPoint(x: 0, y: y + radius))
        }

        func tube(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            let rect = CGRect(x: x0, y: y - radius, width: x1 - x0, height: radius * 2)
            body.fill(Path(roundedRect: rect, cornerRadius: radius), with: brass(y, radius))
        }

        let valveXs: [CGFloat] = [W * 0.36, W * 0.44, W * 0.52]
        let fingering = note.map { fingerings[$0] } ?? [false, false, false]

        // Lower return loop: down from behind the first valve, along the
        // bottom, and a U-turn back up into the lead pipe at the left.
        let loopX0 = W * 0.19, loopX1 = valveXs[2]
        tube(loopX0, loopX1, lowY, r * 0.8)
        var uTurn = Path()
        uTurn.addArc(center: CGPoint(x: loopX0, y: (yc + lowY) / 2),
                     radius: (lowY - yc) / 2,
                     startAngle: .degrees(90), endAngle: .degrees(270),
                     clockwise: false)
        body.stroke(uTurn, with: brass((yc + lowY) / 2, (lowY - yc) / 2),
                    lineWidth: r * 1.6)

        // Lead pipe: mouthpiece to bell.
        tube(W * 0.06, W * 0.62, yc, r)

        // Bell flare.
        let bellY = yc
        let rimX = W * 0.88, rimR = H * 0.21
        var bell = Path()
        bell.move(to: CGPoint(x: W * 0.58, y: bellY - r))
        bell.addCurve(to: CGPoint(x: rimX, y: bellY - rimR),
                      control1: CGPoint(x: W * 0.74, y: bellY - r * 1.4),
                      control2: CGPoint(x: W * 0.80, y: bellY - rimR * 0.85))
        bell.addLine(to: CGPoint(x: rimX, y: bellY + rimR))
        bell.addCurve(to: CGPoint(x: W * 0.58, y: bellY + r),
                      control1: CGPoint(x: W * 0.80, y: bellY + rimR * 0.85),
                      control2: CGPoint(x: W * 0.74, y: bellY + r * 1.4))
        bell.closeSubpath()
        body.fill(bell, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.97, green: 0.89, blue: 0.64), location: 0),
                .init(color: Color(red: 0.86, green: 0.68, blue: 0.31), location: 0.5),
                .init(color: Color(red: 0.49, green: 0.35, blue: 0.11), location: 1)
            ]),
            startPoint: CGPoint(x: 0, y: bellY - rimR),
            endPoint: CGPoint(x: 0, y: bellY + rimR)))
        let rimRect = CGRect(x: rimX - rimR * 0.10, y: bellY - rimR,
                             width: rimR * 0.20, height: rimR * 2)
        body.stroke(Path(ellipseIn: rimRect),
                    with: .color(Color(red: 0.97, green: 0.91, blue: 0.75)),
                    lineWidth: max(2, H * 0.008))

        // Mouthpiece.
        body.fill(Path(roundedRect: CGRect(x: W * 0.02, y: yc - r * 1.5,
                                           width: W * 0.05, height: r * 3),
                       cornerRadius: r),
                  with: .color(Color(white: 0.90)))

        // Valve casings between the lead pipe and the lower loop, with
        // caps that sink when their valve is down.
        for (index, x) in valveXs.enumerated() {
            let casing = CGRect(x: x - r * 1.1, y: yc - r * 1.1,
                                width: r * 2.2, height: (lowY - yc) + r * 2.0)
            body.fill(Path(roundedRect: casing, cornerRadius: r * 0.9),
                      with: brass((yc + lowY) / 2, r * 1.1))

            let pressed = fingering[index]
            let capTop = yc - r * 1.1 - (pressed ? H * 0.035 : H * 0.075)
            // Stem.
            body.fill(Path(CGRect(x: x - r * 0.28, y: capTop + r,
                                  width: r * 0.56, height: (yc - r) - capTop)),
                      with: .color(Color(white: 0.85)))
            // Finger button.
            let capR = r * 1.05
            body.fill(Path(ellipseIn: CGRect(x: x - capR, y: capTop - capR * 0.6,
                                             width: capR * 2, height: capR * 1.7)),
                      with: .radialGradient(
                        Gradient(colors: [Color(white: 0.98), Color(white: 0.62)]),
                        center: CGPoint(x: x - capR * 0.3, y: capTop),
                        startRadius: 0, endRadius: capR * 1.8))
        }

        // Sound arcs from the bell while playing, colored by note.
        if let note {
            let color = RainbowPalette.colors[[0, 3, 5, 7][note]]
            let origin = CGPoint(x: rimX + rimR * 0.15, y: bellY)
            for i in 0..<3 {
                let radius = rimR * (0.55 + 0.45 * CGFloat(i))
                var arc = Path()
                arc.addArc(center: origin, radius: radius,
                           startAngle: .degrees(-55), endAngle: .degrees(55),
                           clockwise: false)
                body.stroke(arc, with: .color(color.opacity(0.75 - 0.2 * Double(i))),
                            lineWidth: max(3, H * 0.012))
            }
        }
    }
}
