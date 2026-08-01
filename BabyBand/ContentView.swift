import SwiftUI

enum Instrument: String, CaseIterable {
    case drums
    case guitar
    case xylophone
    case trombone
    case trumpet
    case piano
    case bongos
    case tongueDrum = "tonguedrum"

    var title: String {
        switch self {
        case .drums: return "Drums"
        case .guitar: return "Guitar"
        case .xylophone: return "Xylophone"
        case .trombone: return "Trombone"
        case .trumpet: return "Trumpet"
        case .piano: return "Piano"
        case .bongos: return "Bongos"
        case .tongueDrum: return "Tongue Drum"
        }
    }

    @ViewBuilder var icon: some View {
        switch self {
        case .drums: Text("🥁").font(.system(size: 44))
        case .guitar: Text("🎸").font(.system(size: 44))
        case .xylophone: XylophoneIcon()
        case .trombone: TromboneIcon()   // 🎺 is a trumpet, so hand-drawn
        case .trumpet: Text("🎺").font(.system(size: 44))
        case .piano: Text("🎹").font(.system(size: 44))
        case .bongos: Text("🪘").font(.system(size: 44))
        case .tongueDrum: TongueDrumIcon()
        }
    }
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
                case .xylophone: XylophoneView()
                case .trombone: TromboneView()
                case .trumpet: TrumpetView()
                case .piano: PianoView()
                case .bongos: BongosView()
                case .tongueDrum: TongueDrumView()
                }
            }

            // Visible parent gate: hold the ♪ button 1.5 s to switch.
            VStack {
                HStack {
                    Spacer()
                    GateButton {
                        showSwitcher = true
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                }
                Spacer()
            }

            if showSwitcher {
                InstrumentSwitcher(
                    current: instrument,
                    select: { choice in
                        if choice != .trombone {
                            AudioEngine.shared.tromboneStop()
                        }
                        if choice != .trumpet {
                            AudioEngine.shared.trumpetStop()
                        }
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
