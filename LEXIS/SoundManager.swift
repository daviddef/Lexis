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

    // MARK: - Synthesis primitives
    //
    // Everything is built by rendering component waveforms into raw sample
    // arrays and MIXING them into one buffer, then playing that single buffer.
    // This matters because play() below uses .interrupts (a new buffer cancels
    // the one still sounding) — so two separate play() calls never actually
    // stack. Anything that should be heard together (a boom under a crack, an
    // arpeggio tail on a combo) has to live in the same buffer.

    // A smooth raised-cosine attack into a gentle power-curve decay. Replaces
    // the old near-instant attack, so tones sound rounded rather than clicking
    // on. `progress` is 0…1 across the note.
    private static func envelope(_ progress: Double, attack: Double = 0.06) -> Double {
        if progress < attack {
            return 0.5 - 0.5 * cos(.pi * progress / max(attack, 0.0001))
        }
        let rel = (progress - attack) / (1 - attack)
        return pow(1 - rel, 1.4)
    }

    // A tone rendered with harmonic partials (fundamental + octave + fifth by
    // default) so it reads as a warm, full note rather than a bare sine beep.
    private static func renderTone(frequency: Double, duration: Double, volume: Double,
                                   partials: [(mult: Double, amp: Double)] = [(1, 1.0), (2, 0.32), (3, 0.12)]) -> [Float] {
        let frameCount = Int(sampleRate * duration)
        guard frameCount > 0 else { return [] }
        let ampSum = partials.reduce(0) { $0 + $1.amp }
        var out = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let progress = Double(frame) / Double(frameCount)
            var s = 0.0
            for p in partials { s += sin(2.0 * .pi * frequency * p.mult * t) * p.amp }
            s /= ampSum
            out[frame] = Float(s * envelope(progress) * volume)
        }
        return out
    }

    // A pitch glide from startFreq to endFreq — the bright "up-chirp" chimes.
    // Rounded envelope + a quiet sub-octave layer for body.
    private static func renderChirp(from startFreq: Double, to endFreq: Double, duration: Double, volume: Double) -> [Float] {
        let frameCount = Int(sampleRate * duration)
        guard frameCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: frameCount)
        var phase = 0.0
        var subPhase = 0.0
        for frame in 0..<frameCount {
            let progress = Double(frame) / Double(frameCount)
            let freq = startFreq + (endFreq - startFreq) * progress
            phase += 2.0 * .pi * freq / sampleRate
            subPhase += 2.0 * .pi * (freq * 0.5) / sampleRate
            let s = sin(phase) + 0.25 * sin(subPhase)
            out[frame] = Float(s / 1.25 * envelope(progress, attack: 0.02) * volume)
        }
        return out
    }

    // Mix component sample arrays (each with a start offset in seconds) into a
    // single buffer, hard-clamped to avoid clipping when layers overlap.
    private static func mix(_ components: [(samples: [Float], offset: Double)]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let total = components.map { Int($0.offset * sampleRate) + $0.samples.count }.max() ?? 0
        guard total > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for i in 0..<total { channel[i] = 0 }
        for comp in components {
            let start = Int(comp.offset * sampleRate)
            for (i, sample) in comp.samples.enumerated() {
                let idx = start + i
                if idx < total { channel[idx] += sample }
            }
        }
        for i in 0..<total { channel[i] = max(-1, min(1, channel[i])) }
        return buffer
    }

    // Convenience: a single-component buffer (the common case).
    private static func tone(frequency: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        mix([(renderTone(frequency: frequency, duration: duration, volume: Double(volume)), 0)])
    }

    private static func chirp(from startFreq: Double, to endFreq: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        mix([(renderChirp(from: startFreq, to: endFreq, duration: duration, volume: Double(volume)), 0)])
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
    /// Haptics.comboEscalation's intensity scaling. From a x5 chain up, a
    /// bright rising arpeggio "stinger" is layered onto the tail (in the same
    /// buffer, since play() interrupts), turning a big chain into a genuine
    /// little flourish rather than just a higher beep.
    static func comboEscalation(_ combo: Int) {
        let base = 523.25 + Double(min(combo, 10)) * 55
        var components: [(samples: [Float], offset: Double)] = [
            (renderChirp(from: base, to: base * 1.3, duration: 0.2, volume: 0.24), 0)
        ]
        if combo >= 5 {
            // Major triad + octave, each note struck a beat after the last.
            let ratios = [1.0, 1.25, 1.5, 2.0]
            let step = 0.075
            for (i, r) in ratios.enumerated() {
                components.append(
                    (renderTone(frequency: base * r, duration: 0.16, volume: 0.16), 0.12 + Double(i) * step)
                )
            }
        }
        play(mix(components))
    }

    /// A perfect-clear or other rare celebratory moment — distinctly
    /// bigger/brighter than a normal word clear. A rising sweep with a full
    /// major-chord arpeggio layered over it.
    static func fanfare() {
        var components: [(samples: [Float], offset: Double)] = [
            (renderChirp(from: 523.25, to: 1046.5, duration: 0.4, volume: 0.26), 0)
        ]
        let notes = [523.25, 659.25, 783.99, 1046.5]   // C E G C
        for (i, f) in notes.enumerated() {
            components.append((renderTone(frequency: f, duration: 0.3, volume: 0.18), Double(i) * 0.1))
        }
        play(mix(components))
    }

    /// Entering the danger zone.
    static func dangerEnter() {
        play(tone(frequency: 98, duration: 0.35, volume: 0.20))
    }

    /// Escalating danger cue: the pitch drops and the volume rises with the
    /// tier (1 = entered, 3 = critical), so the board filling up sounds
    /// progressively more ominous instead of a single one-off warning.
    static func dangerPulse(tier: Int) {
        let freq = max(52.0, 108.0 - Double(tier) * 18.0)          // ~90 / 72 / 54 Hz
        let vol = Float(min(0.34, 0.16 + Double(tier) * 0.06))
        play(tone(frequency: freq, duration: 0.42, volume: vol))
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

    /// Bomb detonation — a low, fast downward boom with a short punchy crack
    /// on top, louder than the ordinary power-up chime so it lands as a
    /// genuinely explosive moment. Both layers are mixed into ONE buffer;
    /// previously they were two play() calls and the second silently
    /// interrupted (cancelled) the first, so the boom never actually sounded.
    static func explosion() {
        play(mix([
            (renderChirp(from: 240, to: 45, duration: 0.45, volume: 0.34), 0),
            (renderTone(frequency: 70, duration: 0.16, volume: 0.30, partials: [(1, 1.0), (2.6, 0.5), (4.1, 0.3)]), 0)
        ]))
    }
}
