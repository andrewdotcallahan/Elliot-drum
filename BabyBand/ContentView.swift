import SwiftUI

enum Instrument: String {
    case drums
    case guitar
}

struct ContentView: View {
    @AppStorage("selectedInstrument") private var storedInstrument = Instrument.drums.rawValue
    @State private var showSwitcher = false

    private var instrument: Instrument {
        Instrument(rawValue: storedInstrument) ?? .drums
    }

    var body: some View {
        ZStack {
            Group {
                switch instrument {
                case .drums: DrumKitView()
                case .guitar: GuitarView()
                }
            }

            // Invisible adult-only gate: hold both top corners for 2 seconds.
            ParentGate {
                showSwitcher = true
            }

            if showSwitcher {
                InstrumentSwitcher(
                    current: instrument,
                    select: { choice in
                        storedInstrument = choice.rawValue
                        showSwitcher = false
                    },
                    dismiss: { showSwitcher = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSwitcher)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
