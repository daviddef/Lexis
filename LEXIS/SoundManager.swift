import AVFoundation

// MARK: - Sound Manager
// Every sound in the game is synthesized at runtime (simple sine-wave tones
// with a short envelope) rather than loaded from bundled audio files — there
// were no sound assets anywhere in the project despite Settings having had a
// "Sound Effects" toggle with no sound behind it. This keeps things dead
// simple (no asset pipeline, no licensing, no file size) while still giving
// every key moment its own distinct, satisfying tone.
@MainActor
enum SoundManager {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static let sampleRate: Double = 44_100
    private static var isSetUp = false

    private static func setUpIfNeeded() {
        guard !isSetUp else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            isSetUp = true
        } catch {
            print("SoundManager: audio engine failed to start — \(error.localizedDescription)")
        }
    }

    // A single sine tone with a quick attack and an exponential-ish fade,
    // so short tones read as a "blip"/"chime" rather than clicking on/off.
    private static func tone(frequency: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        let attackFrames = max(1, Int(sampleRate * 0.005))
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = Double(frame) / Double(frameCount)
            let attack = frame < attackFrames ? Double(frame) / Double(attackFrames) : 1.0
            let decay = pow(1.0 - progress, 1.6)
            let sample = sin(2.0 * .pi * frequency * t) * attack * decay
            channel[frame] = Float(sample) * volume
        }
        return buffer
    }

    // Two tones back to back — used for the little "up-chirp" chimes
    // (word clear, power-up) so they read as a bright confirmation rather
    // than a flat beep.
    private static func chirp(from startFreq: Double, to endFreq: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        var phase = 0.0
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(frameCount)
            let freq = startFreq + (endFreq - startFreq) * progress
            phase += 2.0 * .pi * freq / sampleRate
            let decay = pow(1.0 - progress, 1.3)
            channel[frame] = Float(sin(phase) * decay) * volume
        }
        return buffer
    }

    private static func play(_ buffer: AVAudioPCMBuffer?) {
        guard GameSettings.shared.soundEnabled, let buffer = buffer else { return }
        setUpIfNeeded()
        guard isSetUp else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: - Game events

    /// A soft, low tick every time a piece settles — meant to be felt as
    /// rhythm during fast play, not as a distinct "event" sound.
    static func tileLand() {
        play(tone(frequency: 180, duration: 0.045, volume: 0.10))
    }

    /// Word clear — brighter and slightly higher-pitched for longer words,
    /// so a 3-letter word and a 7-letter word don't sound identical.
    static func wordClear(length: Int) {
        let base = 480.0 + Double(min(length, 8)) * 45
        play(chirp(from: base, to: base * 1.5, duration: 0.16, volume: 0.22))
    }

    /// Combo escalation — pitch climbs with combo depth, so a 5-chain
    /// audibly reads as more exciting than a 2-chain, mirroring
    /// Haptics.comboEscalation's intensity scaling.
    static func comboEscalation(_ combo: Int) {
        let base = 523.25 + Double(min(combo, 10)) * 55
        play(chirp(from: base, to: base * 1.3, duration: 0.2, volume: 0.24))
    }

    /// A perfect-clear or other rare celebratory moment — distinctly
    /// bigger/brighter than a normal word clear.
    static func fanfare() {
        play(chirp(from: 523.25, to: 1046.5, duration: 0.4, volume: 0.28))
    }

    /// Entering the danger zone.
    static func dangerEnter() {
        play(tone(frequency: 98, duration: 0.35, volume: 0.20))
    }

    /// Power-up triggered/resolved (wildcard picked, bomb, dynamite, knock).
    static func powerUp() {
        play(chirp(from: 660, to: 990, duration: 0.14, volume: 0.20))
    }

    /// A rejected action (wall bump, no charge banked, etc).
    static func reject() {
        play(tone(frequency: 130, duration: 0.06, volume: 0.14))
    }

    /// Game over.
    static func gameOver() {
        play(chirp(from: 392, to: 196, duration: 0.5, volume: 0.22))
    }

    /// Bomb detonation — a low, fast downward boom layered under a short
    /// noisy crack, louder than the ordinary power-up chime so it lands as
    /// a genuinely explosive moment.
    static func explosion() {
        play(chirp(from: 240, to: 45, duration: 0.45, volume: 0.34))
        play(tone(frequency: 70, duration: 0.16, volume: 0.30))
    }
}
