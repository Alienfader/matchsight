import Foundation

/// How an insight relates to the facts — shown honestly, never blurred.
public enum InsightBasis: String, Sendable, Equatable, Codable, CaseIterable {
  /// Restates facts.
  case observed
  /// A conclusion drawn from the facts.
  case dataInference = "data_inference"
  /// A general soccer concept (e.g. what a formation usually implies).
  case generalTactics = "general_tactics"
}

public enum InsightSource: String, Sendable, Equatable {
  case model, template, mock
}

/// Exactly the JSON the model returns (strict json_schema).
public struct RawInsight: Sendable, Equatable, Codable {
  public let title: String
  public let body: String
  public let basis: InsightBasis
  public let factIds: [String]

  public init(title: String, body: String, basis: InsightBasis, factIds: [String]) {
    self.title = title
    self.body = body
    self.basis = basis
    self.factIds = factIds
  }
}

/// A validated insight, safe to put on the glasses.
public struct MatchInsight: Sendable, Equatable {
  public static let maxTitle = 28
  public static let maxBody = 150

  public let title: String
  public let body: String
  public let basis: InsightBasis
  public let factIds: [String]
  public let source: InsightSource
  /// The context fingerprint this insight was generated from.
  public let fingerprint: String

  public init(title: String, body: String, basis: InsightBasis, factIds: [String],
              source: InsightSource, fingerprint: String) {
    self.title = title
    self.body = body
    self.basis = basis
    self.factIds = factIds
    self.source = source
    self.fingerprint = fingerprint
  }
}

public enum InsightValidationError: Error, Sendable, Equatable {
  case empty
  case bodyTooLong(Int)
  case unknownFact(String)
  case missingFacts
  case ungroundedClaim(String)
}

/// The grounding gate between the model and the HUD.
public enum InsightValidator {
  /// Claims that need video. CopaHUD only has feed data, so these are
  /// rejected whatever basis the model claims. Matched as whole words
  /// ("impressed" is fine, "press" is not).
  static let visionTerms = ["pressing", "pressed", "press", "high line", "positioning",
                            "off the ball", "tracking back", "body language"]

  /// `requireCitations`: every basis must cite a fact. Used for spoken
  /// (free-form) questions, where an uncited "general tactics" answer could
  /// carry invented specifics.
  public static func validate(_ raw: RawInsight, context: MatchInsightContext,
                              source: InsightSource,
                              requireCitations: Bool = false) throws -> MatchInsight {
    let title = collapse(raw.title)
    let body = collapse(raw.body)
    guard !title.isEmpty, !body.isEmpty else { throw InsightValidationError.empty }
    // Never truncate the body: a cut-off claim can change its meaning.
    guard body.count <= MatchInsight.maxBody else {
      throw InsightValidationError.bodyTooLong(body.count)
    }

    let known = context.factIDs()
    if let unknown = raw.factIds.first(where: { !known.contains($0) }) {
      throw InsightValidationError.unknownFact(unknown)
    }
    if (requireCitations || raw.basis != .generalTactics), raw.factIds.isEmpty {
      throw InsightValidationError.missingFacts
    }
    if let term = visionTerms.first(where: { containsWord($0, in: body) }) {
      throw InsightValidationError.ungroundedClaim(term)
    }

    return MatchInsight(title: truncateTitle(title), body: body, basis: raw.basis,
                        factIds: raw.factIds, source: source,
                        fingerprint: context.fingerprint)
  }

  static func containsWord(_ term: String, in text: String) -> Bool {
    let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
    return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// Collapses every whitespace run (incl. newlines) to one space and trims.
  static func collapse(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  /// "WHY BRAZIL CONTROL THE MIDFIELD BATTLE" → "WHY BRAZIL CONTROL THE…".
  static func truncateTitle(_ title: String) -> String {
    guard title.count > MatchInsight.maxTitle else { return title }
    let head = String(title.prefix(MatchInsight.maxTitle - 1))
    if let space = head.lastIndex(of: " ") {
      return String(head[..<space]) + "…"
    }
    return head + "…"
  }
}
