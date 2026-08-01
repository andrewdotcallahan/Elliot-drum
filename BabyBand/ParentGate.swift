import SwiftUI

/// Visible parent gate: a small dim ♪ button in the top-right corner.
/// Press and hold it for 1.5 s — a progress ring fills while holding,
/// releasing early cancels — to open the instrument switcher. A toddler
/// tap does nothing, and there's nothing hidden for an adult to discover.
struct GateButton: View {
    var onActivate: () -> Void

    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdTask: DispatchWorkItem?

    private let holdDuration: TimeInterval = 1.5

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.28))
            Text("♪")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.55))
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-3)
        }
        .frame(width: 52, height: 52)
        .contentShape(Circle().scale(1.3))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startHold() }
                .onEnded { _ in cancelHold() }
        )
    }

    private func startHold() {
        guard !isHolding else { return }
        isHolding = true
        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1
        }
        let task = DispatchWorkItem {
            if isHolding {
                cancelHold()
                onActivate()
            }
        }
        holdTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
    }

    private func cancelHold() {
        isHolding = false
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            holdProgress = 0
        }
    }
}

/// Adult-facing overlay for switching instruments. Blocks all instrument
/// touches underneath while visible; auto-dismisses after 8 seconds.
struct InstrumentSwitcher: View {
    let current: Instrument
    let select: (Instrument) -> Void
    let dismiss: () -> Void

    @State private var autoDismissTask: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)],
                          spacing: 16) {
                    ForEach(Instrument.allCases, id: \.self) { instrument in
                        instrumentButton(instrument)
                    }
                }
                .frame(maxWidth: 560)

                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(32)
        }
        .onAppear(perform: scheduleAutoDismiss)
        .onDisappear { autoDismissTask?.cancel() }
    }

    private func instrumentButton(_ instrument: Instrument) -> some View {
        Button {
            select(instrument)
        } label: {
            VStack(spacing: 8) {
                instrument.icon
                    .frame(height: 52)
                Text(instrument.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(current == instrument ? Color.blue : Color.white.opacity(0.15))
            )
        }
    }

    private func scheduleAutoDismiss() {
        let task = DispatchWorkItem { dismiss() }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
    }
}

/// Mini steel-tongue-drum icon (no such emoji exists): a teal disc with
/// three radial tongue slots.
struct TongueDrumIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.26, green: 0.53, blue: 0.55),
                                 Color(red: 0.12, green: 0.30, blue: 0.33)],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0, endRadius: 30))
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .stroke(Color(red: 0.05, green: 0.14, blue: 0.16), lineWidth: 2.5)
                    .frame(width: 7, height: 16)
                    .offset(y: 13)
                    .rotationEffect(.degrees(Double(index) * 120))
            }
            Circle()
                .fill(Color(red: 0.05, green: 0.14, blue: 0.16))
                .frame(width: 6, height: 6)
        }
        .frame(width: 48, height: 48)
    }
}

/// Mini slide-trombone icon (the 🎺 emoji is a trumpet, which now uses
/// it): a brass bell tube over the long slide with its U-turn.
struct TromboneIcon: View {
    var body: some View {
        Canvas { context, size in
            let brass = Color(red: 0.87, green: 0.66, blue: 0.27)
            let dark = Color(red: 0.60, green: 0.44, blue: 0.15)

            // Bell tube and flare.
            context.fill(Path(roundedRect: CGRect(x: 2, y: 13, width: 30, height: 7),
                              cornerRadius: 3.5),
                         with: .color(brass))
            var bell = Path()
            bell.move(to: CGPoint(x: 28, y: 13))
            bell.addQuadCurve(to: CGPoint(x: 46, y: 2),
                              control: CGPoint(x: 40, y: 11))
            bell.addLine(to: CGPoint(x: 46, y: 31))
            bell.addQuadCurve(to: CGPoint(x: 28, y: 20),
                              control: CGPoint(x: 40, y: 22))
            bell.closeSubpath()
            context.fill(bell, with: .color(brass))

            // Slide tubes with the U-turn at the far end.
            context.fill(Path(roundedRect: CGRect(x: 4, y: 30, width: 31, height: 4),
                              cornerRadius: 2),
                         with: .color(dark))
            context.fill(Path(roundedRect: CGRect(x: 4, y: 40, width: 31, height: 4),
                              cornerRadius: 2),
                         with: .color(dark))
            var uTurn = Path()
            uTurn.addArc(center: CGPoint(x: 35, y: 37), radius: 5,
                         startAngle: .degrees(-90), endAngle: .degrees(90),
                         clockwise: false)
            context.stroke(uTurn, with: .color(dark), lineWidth: 4)
        }
        .frame(width: 48, height: 48)
    }
}

/// Mini rainbow-bars icon for the xylophone (there is no xylophone emoji).
struct XylophoneIcon: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(RainbowPalette.colors[index * 2])
                    .frame(width: 10, height: 46 - CGFloat(index) * 8)
            }
        }
    }
}
