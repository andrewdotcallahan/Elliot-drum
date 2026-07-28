import SwiftUI

/// Slide trombone: touch anywhere to start the tone, drag along the slide
/// axis to gliss — extending the slide lowers the pitch, a full octave
/// from Bb3 down to Bb2. Monophonic like the real thing. Drawn in a
/// Canvas that rotates for portrait (bell points down, slide extends
/// toward the bottom edge).
struct TromboneView: View {
    @State private var slidePosition: Double = 0    // 0 closed .. 1 fully out
    @State private var shownPosition: Double = 0    // eased display position
    @State private var isPlaying = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    Self.draw(context: context, size: size, slide: shownPosition)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pos = Self.axisPosition(value.location, in: geo.size)
                                slidePosition = pos
                                if isPlaying {
                                    AudioEngine.shared.tromboneGlide(to: pos)
                                } else {
                                    isPlaying = true
                                    AudioEngine.shared.tromboneStart(position: pos)
                                }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    shownPosition = pos
                                }
                            }
                            .onEnded { _ in
                                isPlaying = false
                                AudioEngine.shared.tromboneStop()
                            }
                    )
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            AudioEngine.shared.tromboneStop()
        }
    }

    static func axisPosition(_ point: CGPoint, in size: CGSize) -> Double {
        let long = max(size.width, size.height)
        let value = size.width > size.height ? point.x : point.y
        return min(1, max(0, (value - long * 0.15) / (long * 0.70)))
    }

    // MARK: - Drawing (port of the web canvas trombone)

    static func draw(context: GraphicsContext, size: CGSize, slide: Double) {
        let w = size.width, h = size.height

        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(
                        Gradient(colors: [Color(red: 0.17, green: 0.12, blue: 0.16),
                                          Color(red: 0.09, green: 0.06, blue: 0.10)]),
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

        let yc = H * 0.50
        let r = H * 0.040
        let bellY = yc - H * 0.13
        let s1 = yc + H * 0.06, s2 = yc + H * 0.19

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

        // Bell tube and flare.
        tube(W * 0.10, W * 0.62, bellY, r)
        let rimX = W * 0.88, rimR = H * 0.24
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
        body.fill(Path(roundedRect: CGRect(x: W * 0.045, y: bellY - r * 1.5,
                                           width: W * 0.055, height: r * 3),
                       cornerRadius: r),
                  with: .color(Color(white: 0.90)))

        // Inner slide tubes (thin, fixed) + brace.
        tube(W * 0.12, W * 0.52, s1, r * 0.55)
        tube(W * 0.12, W * 0.52, s2, r * 0.55)
        let braceRect = CGRect(x: W * 0.125 - r * 0.5, y: bellY - r * 0.6,
                               width: r, height: (s2 - bellY) + r * 1.2)
        body.fill(Path(roundedRect: braceRect, cornerRadius: r * 0.5),
                  with: brass((bellY + s2) / 2, (s2 - bellY) / 2))

        // Outer slide: extends with the touch, U-turn at the far end.
        let ext = W * (0.30 + 0.42 * slide)
        let sx0 = W * 0.16, sx1 = sx0 + ext
        tube(sx0, sx1, s1, r * 0.85)
        tube(sx0, sx1, s2, r * 0.85)
        var uTurn = Path()
        uTurn.addArc(center: CGPoint(x: sx1, y: (s1 + s2) / 2),
                     radius: (s2 - s1) / 2,
                     startAngle: .degrees(-90), endAngle: .degrees(90),
                     clockwise: false)
        body.stroke(uTurn, with: brass((s1 + s2) / 2, (s2 - s1) / 2), lineWidth: r * 1.7)
        // Slide grip brace.
        let gripRect = CGRect(x: sx0 + r * 0.2, y: s1 - r,
                              width: r * 1.2, height: (s2 - s1) + r * 2)
        body.fill(Path(roundedRect: gripRect, cornerRadius: r * 0.5),
                  with: brass((s1 + s2) / 2, (s2 - s1) / 2))
    }
}
