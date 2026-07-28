import AVFoundation

/// Preloads every sound into memory and plays them with minimal latency
/// through a round-robin pool of player nodes, so many sounds can overlap
/// (multitouch drumming, fast strums). Everything is guarded: a missing
/// or unreadable file simply produces silence, never a crash.
final class AudioEngine {
    static let shared = AudioEngine()

    static let soundNames: [String] =
        ["kick", "snare", "hihat", "tom_hi", "tom_floor", "cymbal", "ride"]
        + (1...6).map { "guitar_s\($0)" }
        + (1...8).map { "xylo_\($0)" }
        + (1...8).map { "piano_\($0)" }
        + ["conga_lo", "conga_mid", "bongo_hi"]

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let poolSize = 12
    private var observers: [NSObjectProtocol] = []

    // Trombone: a seamless sustain loop pitch-bent through a varispeed
    // unit; the slide UI glides the rate. Monophonic by design.
    private let trombonePlayer = AVAudioPlayerNode()
    private let tromboneVarispeed = AVAudioUnitVarispeed()
    private var tromboneBuffer: AVAudioPCMBuffer?
    private var tromboneFadeGeneration = 0

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
            buffers[name] = Self.loadBuffer(named: name)
        }
        tromboneBuffer = Self.loadBuffer(named: "trombone")
    }

    private static func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        let url = Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
        guard let url,
              let file = try? AVAudioFile(forReading: url),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

    private func buildEngine() {
        let format = buffers.values.first?.format
        for _ in 0..<poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        if let tromboneBuffer {
            engine.attach(trombonePlayer)
            engine.attach(tromboneVarispeed)
            engine.connect(trombonePlayer, to: tromboneVarispeed, format: tromboneBuffer.format)
            engine.connect(tromboneVarispeed, to: engine.mainMixerNode, format: tromboneBuffer.format)
        }
        engine.prepare()
    }

    // MARK: - Trombone

    /// position 0 = slide closed (Bb3) ... 1 = fully out (one octave down).
    func tromboneStart(position: Double) {
        guard let buffer = tromboneBuffer else { return }
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }
        tromboneVarispeed.rate = Float(pow(2.0, -position))
        trombonePlayer.stop()
        trombonePlayer.volume = 0
        trombonePlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        trombonePlayer.play()
        rampTromboneVolume(to: 1.0, over: 0.05)
    }

    func tromboneGlide(to position: Double) {
        tromboneVarispeed.rate = Float(pow(2.0, -position))
    }

    func tromboneStop() {
        guard trombonePlayer.isPlaying else { return }
        rampTromboneVolume(to: 0.0, over: 0.12) { [weak self] in
            self?.trombonePlayer.stop()
        }
    }

    /// Short stepped fade (the node's volume has no built-in ramp); a new
    /// ramp invalidates any ramp still in flight.
    private func rampTromboneVolume(to target: Float, over duration: TimeInterval,
                                    completion: (() -> Void)? = nil) {
        tromboneFadeGeneration += 1
        let generation = tromboneFadeGeneration
        let steps = 6
        let start = trombonePlayer.volume
        for step in 1...steps {
            let fraction = Float(step) / Float(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(step) / Double(steps)) { [weak self] in
                guard let self, self.tromboneFadeGeneration == generation else { return }
                self.trombonePlayer.volume = start + (target - start) * fraction
                if step == steps { completion?() }
            }
        }
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
