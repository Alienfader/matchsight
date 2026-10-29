import Foundation

/// What the fan asked: one of the phone's preset questions, or a question
/// asked aloud (transcribed by Muse Voice Transcribe). Either way the model
/// only sees fixed rules + match facts, and the answer is validated.
public enum InsightQuestion: Sendable, Hashable {
  case matchStory, formation, substitutionImpact, playerToWatch
  /// Asked by the app at full time, not a phone button.
  case fullTimeRecap
  case spoken(String)

  /// The phone's preset buttons, in display order.
  public static let presets: [InsightQuestion] = [.matchStory, .formation,
                                                  .substitutionImpact, .playerToWatch]
  public static let maxSpokenLength = 200

  public var prompt: String {
    switch self {
    case .matchStory: return "What is the story of this match so far?"
    case .formation: return "What do the two formations suggest about how each team is set up?"
    case .substitutionImpact: return "What did the most recent substitution change?"
    case .playerToWatch: return "Which player should I watch right now, based on the facts?"
    case .fullTimeRecap: return "The match is over. Sum it up: the result and what decided it."
    case .spoken(let text):
      let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      return String(collapsed.prefix(Self.maxSpokenLength))
    }
  }

  public var isSpoken: Bool {
    if case .spoken = self { return true }
    return false
  }

  /// Stable short name for logs and tests.
  public var label: String {
    switch self {
    case .matchStory: return "matchStory"
    case .formation: return "formation"
    case .substitutionImpact: return "substitutionImpact"
    case .playerToWatch: return "playerToWatch"
    case .fullTimeRecap: return "fullTimeRecap"
    case .spoken: return "spoken"
    }
  }
}

/// Failure vocabulary for insight generation. Callers fall back to
/// `InsightTemplate` on any of these; cancellation surfaces as
/// `CancellationError` instead.
public enum InsightError: Error, Sendable, Equatable {
  case unauthorized
  case rateLimited
  case timeout
  /// Non-2xx status plus the API's error message (or a short body slice) —
  /// never the request, so no key can leak into it.
  case http(Int, String?)
  /// Transport failure other than a timeout (offline, DNS, TLS…).
  case network(String)
  case malformedResponse(String)
  case invalid(InsightValidationError)
}

/// The AI seam: the app talks to this, never to a concrete model API.
public protocol MatchInsightService: Sendable {
  func insight(for context: MatchInsightContext, question: InsightQuestion) async throws -> MatchInsight
}

/// Deterministic stand-in for tests and demo mode: returns the data-only
/// template, honestly marked `.mock`.
public struct MockMatchInsightService: MatchInsightService {
  private let delay: Duration
  private let failure: InsightError?

  public init(delay: Duration = .zero, failure: InsightError? = nil) {
    self.delay = delay
    self.failure = failure
  }

  public func insight(for context: MatchInsightContext,
                      question: InsightQuestion) async throws -> MatchInsight {
    try await Task.sleep(for: delay)
    if let failure { throw failure }
    let t = InsightTemplate.make(context: context)
    return MatchInsight(title: t.title, body: t.body, basis: t.basis, factIds: t.factIds,
                        source: .mock, fingerprint: t.fingerprint)
  }
}
