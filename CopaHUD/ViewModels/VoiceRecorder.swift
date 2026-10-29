import AVFoundation
import Observation
import CopaHUDCore

/// Push-to-talk capture for "ask the analyst by voice". Uses the iPhone
/// microphone only (no Bluetooth option, so the glasses link is left alone)
/// and converts to the 16 kHz mono 16-bit PCM that Muse Voice Transcribe
/// accepts. Capped at 15 s.
///
/// Two ways to run:
///  • **Ready** (`arm()`): while the glasses are connected the mic runs
///    continuously and everything is discarded until a hold begins. iOS won't
///    let an app *start* the mic in the background (a locked phone), but it
///    keeps a running one going thanks to the `audio` background mode — so a
///    pinch-and-hold works with the phone in a pocket. iOS shows the mic
///    indicator the whole time.
///  • **On demand**: `start()` from idle opens the mic just for the question
///    (the phone's hold-to-ask button with the app on screen).
///
/// Category `.playAndRecord` with `.mixWithOthers` keeps other audio on the
/// phone playing while the mic stays ready; without `.allowBluetooth` the
/// input stays on the iPhone mic and never re-routes the glasses' link.
/// `.allowBluetoothA2DP` is output only: goal chimes and spoken answers can
/// play on the glasses' speakers while the mic stays on the phone.
@Observable
@MainActor
final class VoiceRecorder {
  /// idle → starting (permission/engine) → running → idle. `capture` says
  /// whether the running mic is keeping audio (a hold) or discarding it.
  private enum Phase { case idle, starting, running, stopping }

  private var phase: Phase = .idle
  /// The mic stays running between questions (glasses connected).
  private var armed = false
  var isRecording: Bool { phase == .running && capture.isCapturing }
  var isArmed: Bool { armed && phase == .running }
  private(set) var lastError: String?

  static let sampleRate = 16000.0
  static let maxSeconds = 15.0
  static let minSeconds = 0.3

  @ObservationIgnored private let engine = AVAudioEngine()
  @ObservationIgnored private var capture = VoiceCaptureBuffer(maxSamples: Int(maxSeconds * sampleRate))
  @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

  /// Keeps the mic running, discarding audio, until `disarm()`. Call while
  /// the app is in the foreground. Returns false (with `lastError`) on failure.
  @discardableResult
  func arm() async -> Bool {
    armed = true
    observeInterruptions()
    if phase == .running { return true }
    return await openMic()
  }

  /// Stops the always-ready mic (glasses disconnected or setting off).
  func disarm() {
    armed = false
    guard phase == .running, !capture.isCapturing else { return }
    closeMic()
  }

  /// Starts keeping audio for a question; opens the mic first if it isn't
  /// already running (phone button, app on screen).
  func start() async {
    lastError = nil
    if phase == .idle {
      guard await openMic() else { return }
    }
    guard phase == .running, !capture.isCapturing else { return }
    capture.begin()
  }

  /// Ends the question and returns it as WAV, or nil when it was too short
  /// to be a question. The mic keeps running when armed.
  func stop() async -> Data? {
    guard phase == .running, capture.isCapturing else { return nil }
    // Let conversions already queued from the audio thread land.
    try? await Task.sleep(for: .milliseconds(100))
    let captured = capture.end()
    if !armed { closeMic() }
    guard Double(captured.count) >= Self.minSeconds * Self.sampleRate else { return nil }
    return WAVEncoder.pcm16Mono(captured, sampleRate: Int(Self.sampleRate))
  }

  // MARK: - Mic

  private func openMic() async -> Bool {
    guard phase == .idle else { return phase == .running }
    phase = .starting
    lastError = nil
    guard await AVAudioApplication.requestRecordPermission() else {
      lastError = "Microphone access needed"
      phase = .idle
      return false
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP])
      try session.setActive(true)
    } catch {
      lastError = "Microphone unavailable (\(error.localizedDescription))"
      phase = .idle
      return false
    }

    let input = engine.inputNode
    let inFormat = input.outputFormat(forBus: 0)
    let rate = Self.sampleRate
    guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate,
                                        channels: 1, interleaved: true),
          let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
      lastError = "Microphone format unsupported"
      phase = .idle
      return false
    }

    input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
      // Audio thread: convert this buffer to 16 kHz Int16, then hand it to the main actor.
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * rate / inFormat.sampleRate) + 32
      guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
      var fed = false
      var error: NSError?
      converter.convert(to: out, error: &error) { _, status in
        if fed { status.pointee = .noDataNow; return nil }
        fed = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, let channel = out.int16ChannelData else { return }
      let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
      Task { @MainActor [weak self] in self?.capture.append(chunk) }
    }

    do {
      engine.prepare()
      try engine.start()
      phase = .running
      return true
    } catch {
      input.removeTap(onBus: 0)
      lastError = "Microphone unavailable (\(error.localizedDescription))"
      phase = .idle
      return false
    }
  }

  private func closeMic() {
    phase = .stopping
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    _ = capture.end()
    phase = .idle
  }

  /// A phone call or Siri stops the engine; re-open the ready mic afterwards.
  private func observeInterruptions() {
    guard interruptionObserver == nil else { return }
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] note in
      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch type {
        case .began:
          if self.phase == .running { self.closeMic() }
        case .ended:
          if self.armed { _ = await self.openMic() }
        default:
          break
        }
      }
    }
  }
}
