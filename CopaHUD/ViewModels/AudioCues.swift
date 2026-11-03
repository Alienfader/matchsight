import AVFoundation
import CopaHUDCore

/// Sounds and speech for the glasses' speakers: while connected, the glasses
/// are the phone's Bluetooth headphones, so a goal chime reaches the fan
/// even with their eyes on the TV. The chimes are generated here (no audio
/// files). Every sound logs the output it went to, so the debug log shows
/// whether it reached the glasses or the phone.
@MainActor
final class AudioCues {
  /// Debug log sink (GlassesViewModel.dbg).
  var log: (String) -> Void = { _ in }

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let synth = AVSpeechSynthesizer()
  /// The ElevenLabs answer being fetched or played.
  private var cloudTask: Task<Void, Never>?
  private var cloudPlayer: AVAudioPlayer?
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
  private var attached = false

  func play(_ cue: AudioCue) {
    guard prepareSession(), startEngine(),
          let buffer = Self.buffer(for: cue, format: format) else { return }
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    if !player.isPlaying { player.play() }
    log("audio: \(cue) → \(route)")
  }

  /// The voice picked in Settings (an identifier), or nil for the best one installed.
  var voiceId: String?

  /// Settings → Voice value for the ElevenLabs voice (read through the Worker).
  static let cloudVoiceId = "elevenlabs"
  /// The Worker's text-to-speech route and the app token, when set up. Read
  /// at each answer, so proxy settings saved after launch apply at once.
  var cloud: () -> (url: URL, token: String)? = { nil }

  func speak(_ text: String) {
    guard prepareSession() else { return }
    stopSpeaking()
    if voiceId == Self.cloudVoiceId, let cloud = cloud() {
      speakOnline(text, via: cloud)
    } else {
      speakOnPhone(text)
    }
  }

  /// ElevenLabs through the Worker; the iPhone voice if it fails or is slow,
  /// so an answer is never lost. Never blocks the HUD: it runs in a task.
  private func speakOnline(_ text: String, via cloud: (url: URL, token: String)) {
    let started = Date()
    cloudTask = Task { [weak self] in
      var request = URLRequest(url: cloud.url, timeoutInterval: 4)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(cloud.token, forHTTPHeaderField: "X-CopaHUD-Token")
      request.httpBody = try? JSONEncoder().encode(["text": String(text.prefix(800))])
      let result = try? await URLSession.shared.data(for: request)
      guard let self, !Task.isCancelled else { return }
      let status = (result?.1 as? HTTPURLResponse)?.statusCode ?? 0
      let took = String(format: "%.1f", Date().timeIntervalSince(started))
      guard status == 200, let data = result?.0, let player = try? AVAudioPlayer(data: data) else {
        self.log("audio: ElevenLabs failed (status \(status), \(took) s) → iPhone voice")
        self.speakOnPhone(text)
        return
      }
      self.cloudPlayer = player
      player.play()
      self.log("audio: ElevenLabs \(data.count / 1024) KB in \(took) s → \(self.route)")
    }
  }

  private func speakOnPhone(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    let voice = Self.voice(id: voiceId)
    utterance.voice = voice
    // The compact voices sound rushed at the default rate; the natural ones don't.
    utterance.rate = voice?.quality == .default ? 0.52 : AVSpeechUtteranceDefaultSpeechRate
    synth.speak(utterance)
    log("audio: speaking \(text.count) characters, voice \(voice?.name ?? "default") (\(Self.qualityName(voice))) → \(route)")
  }

  // MARK: - Voices

  /// English voices installed on the phone, the most natural first. iOS ships
  /// the compact ones; Enhanced and Premium voices are downloaded in iOS
  /// Settings → Accessibility → Spoken Content → Voices → English.
  static func englishVoices() -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
      .sorted { a, b in
        let (ra, rb) = (rank(a.quality), rank(b.quality))
        if ra != rb { return ra > rb }
        if (a.language == "en-US") != (b.language == "en-US") { return a.language == "en-US" }
        return a.name < b.name
      }
  }

  /// The picked voice if it's still installed, else the most natural one.
  static func voice(id: String?) -> AVSpeechSynthesisVoice? {
    if let id, let picked = AVSpeechSynthesisVoice(identifier: id) { return picked }
    return englishVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")
  }

  static func qualityName(_ voice: AVSpeechSynthesisVoice?) -> String {
    switch voice?.quality {
    case .premium: return "Premium"
    case .enhanced: return "Enhanced"
    default: return "Compact"
    }
  }

  private static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
    switch quality {
    case .premium: return 2
    case .enhanced: return 1
    default: return 0
    }
  }

  /// A new question is starting: don't talk over it (or into the mic).
  func stopSpeaking() {
    cloudTask?.cancel()
    cloudTask = nil
    cloudPlayer?.stop()
    cloudPlayer = nil
    if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
  }

  // MARK: - Session and engine

  /// Plays alongside other audio. When the always-ready mic holds the
  /// session (.playAndRecord, which allows Bluetooth A2DP output) it's left
  /// as it is; otherwise a playback session is enough.
  private func prepareSession() -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .playAndRecord {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      }
      try session.setActive(true)
      return true
    } catch {
      log("audio: session unavailable (\(error.localizedDescription))")
      return false
    }
  }

  /// Started lazily; a route change stops the engine, so it restarts here.
  private func startEngine() -> Bool {
    if !attached {
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: format)
      attached = true
    }
    guard !engine.isRunning else { return true }
    do {
      try engine.start()
      return true
    } catch {
      log("audio: engine failed (\(error.localizedDescription))")
      return false
    }
  }

  private var route: String {
    AVAudioSession.sharedInstance().currentRoute.outputs
      .map { "\($0.portType.rawValue) \($0.portName)" }.joined(separator: ", ")
  }

  // MARK: - Chimes

  /// Notes as (frequency Hz, start s); each rings and fades over `ring` s.
  private static func notes(for cue: AudioCue) -> (notes: [(Double, Double)], ring: Double) {
    switch cue {
    case .goal:     return ([(523.25, 0), (659.25, 0.11), (783.99, 0.22), (1046.5, 0.33)], 0.55)  // C E G C up
    case .redCard:  return ([(392.0, 0), (311.13, 0.26)], 0.5)                                     // G down to E♭
    case .varCheck: return ([(880.0, 0), (880.0, 0.2)], 0.14)                                      // two short beeps
    case .whistle:  return ([(1760.0, 0)], 0.7)                                                    // one long tone
    }
  }

  private static func buffer(for cue: AudioCue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let (notes, ring) = notes(for: cue)
    let rate = format.sampleRate
    let length = (notes.map(\.1).max() ?? 0) + ring
    let frames = AVAudioFrameCount(length * rate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
          let samples = buffer.floatChannelData?[0] else { return nil }
    buffer.frameLength = frames
    for i in 0..<Int(frames) {
      let t = Double(i) / rate
      var value = 0.0
      for (frequency, start) in notes where t >= start && t < start + ring {
        let local = t - start
        let attack = min(1, local / 0.008)                 // no click at the start
        let decay = exp(-4.5 * local / ring)
        var tone = sin(2 * .pi * frequency * local)
        if cue == .whistle { tone *= 0.75 + 0.25 * sin(2 * .pi * 28 * local) }  // a little trill
        value += tone * attack * decay
      }
      samples[i] = Float(value * 0.32)
    }
    return buffer
  }
}
