import AVFoundation

/// Preloads every sound into memory and plays them with minimal latency
/// through a round-robin pool of player nodes, so many sounds can overlap
/// (multitouch drumming, fast strums). Everything is guarded: a missing
/// or unreadable file simply produces silence, never a crash.
final class AudioEngine {
    static let shared = AudioEngine()

    static let soundNames = [
        "kick", "snare", "hihat", "tom_hi", "tom_floor", "cymbal", "ride",
        "guitar_s1", "guitar_s2", "guitar_s3", "guitar_s4", "guitar_s5", "guitar_s6"
    ]

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let poolSize = 12
    private var observers: [NSObjectProtocol] = []

    private init() {
        configureSession()
        loadBuffers()
        buildEngine()
        startEngine()
        observeSessionEvents()
    }

    /// Play a preloaded sound right now. Safe to call from gesture handlers.
    func play(_ name: String) {
        guard let buffer = buffers[name] else { return }
        if !engine.isRunning { startEngine() }
        guard engine.isRunning, !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback so sound comes out even with the mute switch on.
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func loadBuffers() {
        for name in Self.soundNames {
            let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            guard let url,
                  let file = try? AVAudioFile(forReading: url),
                  file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil
            else { continue }
            buffers[name] = buffer
        }
    }

    private func buildEngine() {
        let format = buffers.values.first?.format
        for _ in 0..<poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.prepare()
    }

    private func startEngine() {
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    private func observeSessionEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            if type == .ended {
                self.startEngine()
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !self.engine.isRunning {
                self.startEngine()
            }
        })
    }
}
