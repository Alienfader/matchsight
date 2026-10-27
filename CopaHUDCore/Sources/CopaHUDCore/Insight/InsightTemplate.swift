import Foundation

/// Deterministic, data-only insight shown whenever the model is unavailable,
/// slow, or its answer fails validation. It only restates context facts.
public enum InsightTemplate {
  public static func make(context: MatchInsightContext) -> MatchInsight {
    // Score, then the latest event (event facts start with the minute), then shots.
    let candidates = [
      context.facts.first { $0.text.hasPrefix("Score:") },
      context.facts.last { $0.text.first?.isNumber == true },
      context.facts.first { $0.text.hasPrefix("Shots:") },
    ].compactMap { $0 }

    var used = candidates
    while !used.isEmpty, body(used).count > MatchInsight.maxBody {
      used.removeLast()
    }
    guard !used.isEmpty else {
      return MatchInsight(title: "ANALYST", body: "Waiting for match data.",
                          basis: .observed, factIds: [], source: .template,
                          fingerprint: context.fingerprint)
    }
    return MatchInsight(title: "MATCH SNAPSHOT", body: body(used), basis: .observed,
                        factIds: used.map(\.id), source: .template,
                        fingerprint: context.fingerprint)
  }

  private static func body(_ facts: [InsightFact]) -> String {
    facts.map(\.text).joined(separator: ". ")
  }
}
