import CopaHUDCore
import Foundation
import ImageIO
import Vision

/// Reads candidate shirt numbers from one glasses photo, on the phone, with
/// Apple's text recognition. Only the middle of the picture is read — what
/// the fan is looking at, not a TV's score box in the corner — and bigger,
/// more central text weighs more. The photo is never stored or sent anywhere.
enum ShirtNumberReader {
  /// The centre of the photo, in Vision's normalised coordinates.
  private static let region = CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)

  static func candidates(in photo: Data) async -> [NumberCandidate] {
    guard let source = CGImageSourceCreateWithData(photo as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = (props?[kCGImagePropertyOrientation] as? UInt32)
      .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up

    return await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      request.regionOfInterest = region
      let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
      do { try handler.perform([request]) } catch { return [] }
      return (request.results ?? []).flatMap { observation -> [NumberCandidate] in
        guard let text = observation.topCandidates(1).first?.string else { return [] }
        let box = observation.boundingBox   // relative to the region
        let dx = box.midX - 0.5, dy = box.midY - 0.5
        let centrality = max(0, 1 - (dx * dx + dy * dy).squareRoot() * 1.4)
        let weight = Double(box.height) * Double(centrality)
        // "SAKA 7" → "SAKA", "7": the lookup keeps only bare 1–99.
        return text.split(separator: " ").map { NumberCandidate(text: String($0), weight: weight) }
      }
    }.value
  }
}
