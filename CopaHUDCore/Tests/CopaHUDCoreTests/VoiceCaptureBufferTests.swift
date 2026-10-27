import XCTest
@testable import CopaHUDCore

/// The recorder keeps the mic running while the glasses are connected (so a
/// hold works with the phone locked) and must keep ONLY what is said between
/// hold-start and hold-end.
final class VoiceCaptureBufferTests: XCTestCase {

  func testAudioOutsideAHoldIsDiscarded() {
    var b = VoiceCaptureBuffer(maxSamples: 100)
    b.append([1, 2, 3])
    b.begin()
    b.append([4, 5])
    XCTAssertEqual(b.end(), [4, 5])
    b.append([6, 7])
    b.begin()
    XCTAssertEqual(b.end(), [], "the previous hold's audio and post-hold audio are gone")
  }

  func testCaptureIsCappedAtMaxSamples() {
    var b = VoiceCaptureBuffer(maxSamples: 4)
    b.begin()
    b.append([1, 2, 3])
    b.append([4, 5, 6])
    XCTAssertEqual(b.end(), [1, 2, 3, 4])
  }

  func testIsCapturingFollowsBeginAndEnd() {
    var b = VoiceCaptureBuffer(maxSamples: 4)
    XCTAssertFalse(b.isCapturing)
    b.begin()
    XCTAssertTrue(b.isCapturing)
    _ = b.end()
    XCTAssertFalse(b.isCapturing)
  }
}
