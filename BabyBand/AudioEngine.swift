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
        + (1...8).map { "tongue_\($0)" }
        + ["conga_lo", "conga_mid", "bongo_hi"]

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let poolSize = 12
    private var observers: [NSObjectProtocol] = []

    // Brass: each is a seamless sustain loop pitch-shifted through a
    // varispeed unit — the trombone glides the rate continuously, the
    // trumpet steps it through valve notes. Monophonic by design.
    private let tromboneVoice = SustainedVoice(soundName: "trombone")
    private let trumpetVoice = SustainedVoice(soundName: "trumpet")

    /// Trumpet valve notes, low to high: C4 E4 G4 C5 — a C major
    /// arpeggio, played by rate-shifting the G4 reference loop.
    static let trumpetNoteFrequencies: [Double] = [261.63, 329.63, 392.00, 523.25]
    private static let trumpetLoopFrequency = 392.00

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
        tromboneVoice.attach(to: engine)
        trumpetVoice.attach(to: engine)
        engine.prepare()
    }

    // MARK: - Trombone

    /// position 0 = slide closed (Bb3) ... 1 = fully out (one octave down).
    func tromboneStart(position: Double) {
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }
        tromboneVoice.start(rate: pow(2.0, -position))
    }

    func tromboneGlide(to position: Double) {
        tromboneVoice.glide(rate: pow(2.0, -position))
    }

    func tromboneStop() {
        tromboneVoice.stop()
    }

    // MARK: - Trumpet

    /// note is an index into trumpetNoteFrequencies (0..3, low to high).
    func trumpetStart(note: Int) {
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }
        trumpetVoice.start(rate: Self.trumpetRate(note))
    }

    func trumpetChange(to note: Int) {
        trumpetVoice.glide(rate: Self.trumpetRate(note))
    }

    func trumpetStop() {
        trumpetVoice.stop()
    }

    private static func trumpetRate(_ note: Int) -> Double {
        let index = min(max(note, 0), trumpetNoteFrequencies.count - 1)
        return trumpetNoteFrequencies[index] / trumpetLoopFrequency
    }

    /// One monophonic looped-sustain voice: player -> varispeed -> mixer,
    /// with short stepped volume ramps on start/stop (the node's volume
    /// has no built-in ramp); a new ramp invalidates any ramp in flight.
    private final class SustainedVoice {
        private let player = AVAudioPlayerNode()
        private let varispeed = AVAudioUnitVarispeed()
        private let buffer: AVAudioPCMBuffer?
        private var fadeGeneration = 0

        init(soundName: String) {
            buffer = AudioEngine.loadBuffer(named: soundName)
        }

        func attach(to engine: AVAudioEngine) {
            guard let buffer else { return }
            engine.attach(player)
            engine.attach(varispeed)
            engine.connect(player, to: varispeed, format: buffer.format)
            engine.connect(varispeed, to: engine.mainMixerNode, format: buffer.format)
        }

        func start(rate: Double) {
            guard let buffer else { return }
            varispeed.rate = Float(rate)
            player.stop()
            player.volume = 0
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            player.play()
            ramp(to: 1.0, over: 0.05)
        }

        func glide(rate: Double) {
            varispeed.rate = Float(rate)
        }

        func stop() {
            guard player.isPlaying else { return }
            ramp(to: 0.0, over: 0.12) { [weak self] in
                self?.player.stop()
            }
        }

        private func ramp(to target: Float, over duration: TimeInterval,
                          completion: (() -> Void)? = nil) {
            fadeGeneration += 1
            let generation = fadeGeneration
            let steps = 6
            let start = player.volume
            for step in 1...steps {
                let fraction = Float(step) / Float(steps)
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(step) / Double(steps)) { [weak self] in
                    guard let self, self.fadeGeneration == generation else { return }
                    self.player.volume = start + (target - start) * fraction
                    if step == steps { completion?() }
                }
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
