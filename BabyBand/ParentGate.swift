import SwiftUI

/// Invisible parent gate: an adult must press and hold BOTH top corners
/// of the screen at the same time for 2 seconds to open the instrument
/// switcher. A toddler mashing one spot never triggers it.
struct ParentGate: View {
    var onActivate: () -> Void

    @State private var leftHeld = false
    @State private var rightHeld = false
    @State private var holdTask: DispatchWorkItem?

    private let zoneSize: CGFloat = 90
    private let holdDuration: TimeInterval = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                hotZone(isHeld: $leftHeld)
                Spacer()
                hotZone(isHeld: $rightHeld)
            }
            Spacer()
        }
        .ignoresSafeArea()
        .onChange(of: leftHeld) { _ in updateHoldTimer() }
        .onChange(of: rightHeld) { _ in updateHoldTimer() }
    }

    private func hotZone(isHeld: Binding<Bool>) -> some View {
        Color.clear
            .frame(width: zoneSize, height: zoneSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHeld.wrappedValue {
                            isHeld.wrappedValue = true
                        }
                    }
                    .onEnded { _ in
                        isHeld.wrappedValue = false
                    }
            )
    }

    private func updateHoldTimer() {
        holdTask?.cancel()
        holdTask = nil
        guard leftHeld && rightHeld else { return }
        let task = DispatchWorkItem {
            if leftHeld && rightHeld {
                leftHeld = false
                rightHeld = false
                onActivate()
            }
        }
        holdTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
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

            VStack(spacing: 28) {
                HStack(spacing: 24) {
                    instrumentButton(emoji: "🥁", title: "Drums", value: .drums)
                    instrumentButton(emoji: "🎸", title: "Guitar", value: .guitar)
                }
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

    private func instrumentButton(emoji: String, title: String, value: Instrument) -> some View {
        Button {
            select(value)
        } label: {
            VStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 64))
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            .frame(width: 160, height: 160)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(current == value ? Color.blue : Color.white.opacity(0.15))
            )
        }
    }

    private func scheduleAutoDismiss() {
        let task = DispatchWorkItem { dismiss() }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
    }
}
