import AVFoundation
import QuartzCore

/// Bricks' sounds: calm and meditative. Kalimba notes in one scale (A minor pentatonic, so notes
/// that overlap always sit well), singing bowls, breaths of air, wooden clicks, water drops and a
/// felt thump, all with a little room around them. All made by tools/make_sounds.py.
///
/// Played through one small engine with a few voices, so sounds can overlap without cutting each
/// other off. "Ambient": it mixes with your music and goes quiet with the silent switch.
/// Settings › Sounds turns it all off.
@MainActor
final class Sound {
    static let shared = Sound()

    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private var lastPlayed: [String: CFTimeInterval] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        for _ in 0..<12 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        // Quiet by design: these are background sounds.
        engine.mainMixerNode.outputVolume = 0.55
        for url in Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? [] {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { continue }
            buffers[url.deletingPathExtension().lastPathComponent] = buffer
        }
        try? engine.start()
        // Start again after a call, Siri or a change of headphones.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
    }

    private func restart() {
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    /// Wakes the engine early, so the first sound isn't late.
    func prepare() { _ = buffers.count }

    /// Plays a sound by name. The same sound won't stack up more than once every `gap` seconds.
    func play(_ name: String, volume: Float = 1, gap: Double = 0.03) {
        guard Settings.shared.sound, let buffer = buffers[name] else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < gap { return }
        lastPlayed[name] = now
        if !engine.isRunning { restart() }
        guard engine.isRunning else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = volume
        voice.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.play()
    }

    /// A marimba note on the scale (0 is the lowest; it climbs and wraps round two octaves).
    func note(_ step: Int, volume: Float = 1) {
        play(String(format: "note%02d", min(10, max(0, step))), volume: volume, gap: 0.02)
    }

    /// A bell note on the scale.
    func bell(_ step: Int, volume: Float = 1) {
        play(String(format: "bell%02d", min(10, max(0, step))), volume: volume, gap: 0.02)
    }

    /// Rising bells, one after another (for stars and wins).
    func bells(_ steps: [Int], every: Double = 0.18, volume: Float = 1) {
        for (i, s) in steps.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(every * Double(i)))
                Sound.shared.bell(s, volume: volume)
            }
        }
    }
}
