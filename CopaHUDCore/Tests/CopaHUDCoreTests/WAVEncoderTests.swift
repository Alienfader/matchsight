import XCTest
@testable import CopaHUDCore

/// Muse Voice Transcribe accepts RIFF/WAVE, mono, 16-bit PCM at 16/24 kHz.
/// The encoder must produce exactly that canonical 44-byte header.
final class WAVEncoderTests: XCTestCase {
  private func u32(_ d: Data, _ at: Int) -> UInt32 {
    d.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
  }

  func testWAVHeader() {
    let wav = WAVEncoder.pcm16Mono([1, -1, 256], sampleRate: 16000)
    XCTAssertEqual(wav.count, 50)
    XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
    XCTAssertEqual(u32(wav, 4), 42)                          // file size - 8
    XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
    XCTAssertEqual(String(decoding: wav[12..<16], as: UTF8.self), "fmt ")
    XCTAssertEqual(wav[20], 1)                               // PCM
    XCTAssertEqual(wav[22], 1)                               // mono
    XCTAssertEqual(u32(wav, 24), 16000)                      // sample rate
    XCTAssertEqual(u32(wav, 28), 32000)                      // byte rate
    XCTAssertEqual(wav[32], 2)                               // block align
    XCTAssertEqual(wav[34], 16)                              // bits per sample
    XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
    XCTAssertEqual(u32(wav, 40), 6)
    XCTAssertEqual(Array(wav[44..<50]), [0x01, 0x00, 0xFF, 0xFF, 0x00, 0x01])  // little-endian
  }
}
