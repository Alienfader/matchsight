import Foundation

/// Holds the samples of one push-to-talk question. The app's microphone may
/// run continuously while the glasses are connected; only audio between
/// `begin()` and `end()` is kept, capped at `maxSamples`.
public struct VoiceCaptureBuffer: Sendable {
  public let maxSamples: Int
  public private(set) var isCapturing = false
  private var samples: [Int16] = []

  public init(maxSamples: Int) {
    self.maxSamples = maxSamples
  }

  public mutating func begin() {
    samples = []
    isCapturing = true
  }

  public mutating func append(_ chunk: [Int16]) {
    guard isCapturing else { return }
    let room = maxSamples - samples.count
    guard room > 0 else { return }
    samples.append(contentsOf: chunk.prefix(room))
  }

  /// Ends the hold and hands back what was said.
  public mutating func end() -> [Int16] {
    isCapturing = false
    defer { samples = [] }
    return samples
  }
}
