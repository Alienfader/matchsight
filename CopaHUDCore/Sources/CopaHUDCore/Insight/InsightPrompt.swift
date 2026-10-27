import Foundation

/// Fixed prompt copy + output schema for the AI analyst. The grounding rules
/// here mirror InsightValidator: the prompt asks, the validator enforces.
public enum InsightPrompt {
  public static let system = """
    You are Matchsight's soccer analyst. You write ONE short insight for a fan watching a match on smart glasses.
    Rules:
    - Use ONLY the numbered facts provided. Never invent players, events, numbers or tactics that are not in the facts.
    - You have no video. Never describe pressing, positioning, movement or anything that requires watching the match.
    - basis: "observed" if you restate facts; "data_inference" if you draw a conclusion from the facts; "general_tactics" if you explain a general soccer concept (for example what a formation usually implies).
    - factIds: the IDs of the facts you used, e.g. ["F2","F7"]. Empty only when basis is "general_tactics".
    - title: at most 28 characters, uppercase. body: at most 150 characters, one or two plain sentences, no emoji.
    - If the question cannot be answered from the facts, say so in one short sentence and point to the most relevant fact.
    - If the facts are marked SCRIPTED, they are demo data. Still use only them.
    """

  public static func user(context: MatchInsightContext, question: InsightQuestion) -> String {
    let asked: String
    if case .spoken = question {
      asked = "Question (asked aloud by the fan): \(question.prompt)"
    } else {
      asked = "Question: \(question.prompt)"
    }
    var lines = [asked, "Match: \(context.headline)"]
    if question.isSpoken {
      lines.append("Cite at least one fact, whatever the basis; if the facts can't answer, say so and cite the closest one.")
    }
    if context.isScripted { lines.append("NOTE: all facts are SCRIPTED demo data.") }
    lines.append("Facts:")
    lines.append(contentsOf: context.facts.map { "\($0.id): \($0.text)" })
    return lines.joined(separator: "\n")
  }

  /// Strict json_schema for `RawInsight`: every property required, no extras.
  public static func responseSchema() -> [String: Any] {
    [
      "type": "object",
      "properties": [
        "title": ["type": "string"],
        "body": ["type": "string"],
        "basis": ["type": "string", "enum": InsightBasis.allCases.map(\.rawValue)],
        "factIds": ["type": "array", "items": ["type": "string"]],
      ],
      "required": ["title", "body", "basis", "factIds"],
      "additionalProperties": false,
    ]
  }
}
