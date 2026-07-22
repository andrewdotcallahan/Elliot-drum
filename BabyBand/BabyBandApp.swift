import SwiftUI

@main
struct BabyBandApp: App {
    init() {
        // Warm up the audio engine at launch so the very first hit is instant.
        _ = AudioEngine.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
