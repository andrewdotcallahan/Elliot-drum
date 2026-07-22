import SwiftUI

/// One piece of the drum kit, positioned on a fixed design canvas.
///
/// The kit is drawn with pre-rendered sprites (see tools/drumkit_svg/) that
/// were composed on a 1400x1000-unit canvas (landscape) and a 1000x1800-unit
/// canvas (portrait). `center` and `width` are in those canvas units;
/// `natural` is the sprite's own unit size (its aspect ratio source).
/// `padCenter`/`padRadii` describe the tappable ellipse in sprite units —
/// for pieces that include a stand (hi-hat, ride) the pad covers just the
/// cymbals, not the hardware. Array order is draw order (later = in front).
struct DrumPiece: Identifiable {
    let id: Int
    let sprite: String
    let sound: String
    let isCymbal: Bool
    let center: CGPoint
    let width: CGFloat
    let natural: CGSize
    let padCenter: CGPoint
    let padRadii: CGSize
}

/// A full-kit arrangement: design-canvas size plus the placed pieces.
struct DrumKitLayout {
    let canvas: CGSize
    let pieces: [DrumPiece]
}

/// Elliptical touch pad at a fixed spot inside the sprite's frame.
/// (Slightly larger than the visible piece — toddler fingers.)
struct DrumPadShape: Shape {
    let center: CGPoint
    let radii: CGSize

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radii.width,
            y: center.y - radii.height,
            width: radii.width * 2,
            height: radii.height * 2
        ))
    }
}

struct DrumKitView: View {
    // Sprite natural unit sizes (match the SVG viewBoxes in tools/drumkit_svg/).
    private static let kickSize = CGSize(width: 470, height: 500)
    private static let snareSize = CGSize(width: 360, height: 330)
    private static let tomHiSize = CGSize(width: 310, height: 300)
    private static let tomFloorSize = CGSize(width: 400, height: 400)
    private static let hihatSize = CGSize(width: 330, height: 540)
    private static let crashSize = CGSize(width: 460, height: 230)
    private static let rideSize = CGSize(width: 490, height: 440)

    // Touch pads in sprite units (ellipse over the playable surface).
    private static let kickPad = (CGPoint(x: 235, y: 232), CGSize(width: 225, height: 225))
    private static let snarePad = (CGPoint(x: 180, y: 155), CGSize(width: 190, height: 150))
    private static let tomHiPad = (CGPoint(x: 155, y: 145), CGSize(width: 165, height: 145))
    private static let tomFloorPad = (CGPoint(x: 200, y: 185), CGSize(width: 205, height: 180))
    private static let hihatPad = (CGPoint(x: 165, y: 113), CGSize(width: 175, height: 95))
    private static let crashPad = (CGPoint(x: 230, y: 112), CGSize(width: 235, height: 118))
    private static let ridePad = (CGPoint(x: 245, y: 124), CGSize(width: 240, height: 120))

    /// Wide screens: full GarageBand-style composition on a 1400x1000 canvas.
    /// MUST match tools/drumkit_svg/render_sprites.js (LANDSCAPE table).
    private static let landscape = DrumKitLayout(
        canvas: CGSize(width: 1400, height: 1000),
        pieces: [
            DrumPiece(id: 0, sprite: "drum_crash", sound: "cymbal", isCymbal: true,
                      center: CGPoint(x: 195, y: 225), width: 440, natural: crashSize,
                      padCenter: crashPad.0, padRadii: crashPad.1),
            DrumPiece(id: 1, sprite: "drum_ride", sound: "ride", isCymbal: true,
                      center: CGPoint(x: 1215, y: 364), width: 480, natural: rideSize,
                      padCenter: ridePad.0, padRadii: ridePad.1),
            DrumPiece(id: 2, sprite: "drum_hihat", sound: "hihat", isCymbal: true,
                      center: CGPoint(x: 150, y: 555), width: 320, natural: hihatSize,
                      padCenter: hihatPad.0, padRadii: hihatPad.1),
            DrumPiece(id: 3, sprite: "drum_tom_hi", sound: "tom_hi", isCymbal: false,
                      center: CGPoint(x: 530, y: 365), width: 295, natural: tomHiSize,
                      padCenter: tomHiPad.0, padRadii: tomHiPad.1),
            DrumPiece(id: 4, sprite: "drum_tom_hi", sound: "tom_hi", isCymbal: false,
                      center: CGPoint(x: 830, y: 375), width: 320, natural: tomHiSize,
                      padCenter: tomHiPad.0, padRadii: tomHiPad.1),
            DrumPiece(id: 5, sprite: "drum_kick", sound: "kick", isCymbal: false,
                      center: CGPoint(x: 680, y: 640), width: 460, natural: kickSize,
                      padCenter: kickPad.0, padRadii: kickPad.1),
            DrumPiece(id: 6, sprite: "drum_snare", sound: "snare", isCymbal: false,
                      center: CGPoint(x: 265, y: 720), width: 350, natural: snareSize,
                      padCenter: snarePad.0, padRadii: snarePad.1),
            DrumPiece(id: 7, sprite: "drum_tom_floor", sound: "tom_floor", isCymbal: false,
                      center: CGPoint(x: 1125, y: 690), width: 390, natural: tomFloorSize,
                      padCenter: tomFloorPad.0, padRadii: tomFloorPad.1)
        ]
    )

    /// Tall screens: same kit re-stacked on a 1000x1800 canvas.
    /// MUST match tools/drumkit_svg/render_sprites.js (PORTRAIT table).
    private static let portrait = DrumKitLayout(
        canvas: CGSize(width: 1000, height: 1800),
        pieces: [
            DrumPiece(id: 0, sprite: "drum_crash", sound: "cymbal", isCymbal: true,
                      center: CGPoint(x: 210, y: 240), width: 400, natural: crashSize,
                      padCenter: crashPad.0, padRadii: crashPad.1),
            DrumPiece(id: 1, sprite: "drum_ride", sound: "ride", isCymbal: true,
                      center: CGPoint(x: 790, y: 349), width: 430, natural: rideSize,
                      padCenter: ridePad.0, padRadii: ridePad.1),
            DrumPiece(id: 2, sprite: "drum_hihat", sound: "hihat", isCymbal: true,
                      center: CGPoint(x: 135, y: 900), width: 300, natural: hihatSize,
                      padCenter: hihatPad.0, padRadii: hihatPad.1),
            DrumPiece(id: 3, sprite: "drum_tom_hi", sound: "tom_hi", isCymbal: false,
                      center: CGPoint(x: 365, y: 555), width: 285, natural: tomHiSize,
                      padCenter: tomHiPad.0, padRadii: tomHiPad.1),
            DrumPiece(id: 4, sprite: "drum_tom_hi", sound: "tom_hi", isCymbal: false,
                      center: CGPoint(x: 660, y: 565), width: 305, natural: tomHiSize,
                      padCenter: tomHiPad.0, padRadii: tomHiPad.1),
            DrumPiece(id: 5, sprite: "drum_kick", sound: "kick", isCymbal: false,
                      center: CGPoint(x: 500, y: 985), width: 430, natural: kickSize,
                      padCenter: kickPad.0, padRadii: kickPad.1),
            DrumPiece(id: 6, sprite: "drum_snare", sound: "snare", isCymbal: false,
                      center: CGPoint(x: 255, y: 1420), width: 350, natural: snareSize,
                      padCenter: snarePad.0, padRadii: snarePad.1),
            DrumPiece(id: 7, sprite: "drum_tom_floor", sound: "tom_floor", isCymbal: false,
                      center: CGPoint(x: 755, y: 1430), width: 380, natural: tomFloorSize,
                      padCenter: tomFloorPad.0, padRadii: tomFloorPad.1)
        ]
    )

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let layout = w > h ? Self.landscape : Self.portrait
            let scale = min(w / layout.canvas.width, h / layout.canvas.height)
            let offsetX = (w - layout.canvas.width * scale) / 2
            let offsetY = (h - layout.canvas.height * scale) / 2

            ZStack {
                Image("drum_stage_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                ForEach(layout.pieces) { piece in
                    DrumSpriteView(piece: piece, scale: scale)
                        .position(
                            x: offsetX + piece.center.x * scale,
                            y: offsetY + piece.center.y * scale
                        )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// One tappable sprite. Each piece owns its own zero-distance drag gesture,
/// so several pieces can be hit at the same time (multitouch). Sound fires
/// on touch DOWN. Drums bounce; cymbals bounce, wobble in 3D and flash.
struct DrumSpriteView: View {
    let piece: DrumPiece
    let scale: CGFloat

    @State private var isPressed = false
    @State private var wobble: Double = 0
    @State private var wobbleSign: Double = 1
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0

    var body: some View {
        // Sprite size in points, plus a touch margin around it.
        let spriteW = piece.width * scale
        let spriteH = spriteW * piece.natural.height / piece.natural.width
        let unit = spriteW / piece.natural.width
        let margin = spriteW * 0.06
        let frameW = spriteW + margin * 2
        let frameH = spriteH + margin * 2
        let padCenter = CGPoint(
            x: margin + piece.padCenter.x * unit,
            y: margin + piece.padCenter.y * unit
        )
        let padRadii = CGSize(
            width: piece.padRadii.width * unit,
            height: piece.padRadii.height * unit
        )
        let anchor = UnitPoint(x: padCenter.x / frameW, y: padCenter.y / frameH)

        ZStack {
            Image(piece.sprite)
                .resizable()
                .scaledToFit()
                .frame(width: spriteW, height: spriteH)

            if piece.isCymbal {
                Ellipse()
                    .stroke(Color.white.opacity(0.9), lineWidth: max(2, spriteW * 0.015))
                    .frame(width: padRadii.width * 2, height: padRadii.height * 2)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .position(x: padCenter.x, y: padCenter.y)
            }
        }
        .frame(width: frameW, height: frameH)
        .scaleEffect(isPressed ? (piece.isCymbal ? 0.97 : 0.94) : 1, anchor: anchor)
        .rotation3DEffect(
            .degrees(wobble),
            axis: (x: 1, y: 0.3, z: 0),
            anchor: anchor,
            perspective: 0.6
        )
        .animation(.spring(response: 0.16, dampingFraction: 0.5), value: isPressed)
        .contentShape(DrumPadShape(
            center: padCenter,
            radii: CGSize(width: padRadii.width * 1.12 + margin,
                          height: padRadii.height * 1.12 + margin)
        ))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    AudioEngine.shared.play(piece.sound)
                    if piece.isCymbal {
                        flashRing()
                        wobbleCymbal()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    private func flashRing() {
        ringScale = 1
        ringOpacity = 0.85
        withAnimation(.easeOut(duration: 0.4)) {
            ringScale = 1.22
            ringOpacity = 0
        }
    }

    private func wobbleCymbal() {
        wobbleSign = -wobbleSign
        wobble = 4.5 * wobbleSign
        withAnimation(.spring(response: 0.4, dampingFraction: 0.2)) {
            wobble = 0
        }
    }
}
