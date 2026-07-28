import SwiftUI
import UIKit

/// Raw multitouch bridge: reports every finger independently with a stable
/// id for its lifetime, so instruments can support chords AND glissando
/// drags across keys/bars (SwiftUI's DragGesture tracks only one finger,
/// and per-key gestures never see a finger sliding in from a neighbor).
struct MultiTouchView: UIViewRepresentable {
    var onBegan: (Int, CGPoint) -> Void
    var onMoved: (Int, CGPoint) -> Void
    var onEnded: (Int) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
    }

    final class TouchView: UIView {
        var onBegan: ((Int, CGPoint) -> Void)?
        var onMoved: ((Int, CGPoint) -> Void)?
        var onEnded: ((Int) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                onBegan?(ObjectIdentifier(touch).hashValue, touch.location(in: self))
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                onMoved?(ObjectIdentifier(touch).hashValue, touch.location(in: self))
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                onEnded?(ObjectIdentifier(touch).hashValue)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                onEnded?(ObjectIdentifier(touch).hashValue)
            }
        }
    }
}

/// The shared rainbow used by the xylophone bars and piano key strips.
enum RainbowPalette {
    static let colors: [Color] = [
        Color(red: 0.88, green: 0.29, blue: 0.25),   // #e04a3f
        Color(red: 0.94, green: 0.51, blue: 0.20),   // #ef8332
        Color(red: 0.96, green: 0.77, blue: 0.26),   // #f4c542
        Color(red: 0.35, green: 0.70, blue: 0.41),   // #58b368
        Color(red: 0.23, green: 0.66, blue: 0.63),   // #3aa8a0
        Color(red: 0.26, green: 0.53, blue: 0.84),   // #4287d6
        Color(red: 0.44, green: 0.42, blue: 0.85),   // #6f6bd8
        Color(red: 0.71, green: 0.40, blue: 0.78)    // #b465c7
    ]
}
