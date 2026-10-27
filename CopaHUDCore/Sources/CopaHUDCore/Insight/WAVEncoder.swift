import Foundation

/// Canonical RIFF/WAVE (44-byte header) for mono 16-bit PCM — the format
/// Muse Voice Transcribe accepts (16 or 24 kHz).
public enum WAVEncoder {
  public static func pcm16Mono(_ samples: [Int16], sampleRate: Int = 16000) -> Data {
    let dataSize = UInt32(samples.count * 2)
    var wav = Data(capacity: 44 + Int(dataSize))

    func append(_ text: String) { wav.append(contentsOf: Array(text.utf8)) }
    func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
    func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }

    append("RIFF"); append32(36 + dataSize); append("WAVE")
    append("fmt "); append32(16)
    append16(1)                              // PCM
    append16(1)                              // mono
    append32(UInt32(sampleRate))
    append32(UInt32(sampleRate * 2))         // byte rate
    append16(2)                              // block align
    append16(16)                             // bits per sample
    append("data"); append32(dataSize)
    for s in samples { withUnsafeBytes(of: s.littleEndian) { wav.append(contentsOf: $0) } }
    return wav
  }
}
