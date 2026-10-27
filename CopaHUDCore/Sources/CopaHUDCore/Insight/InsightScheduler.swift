import Foundation

/// When to auto-refresh the insight page. Pure: the coordinator injects `now`.
/// Unchanged match data never re-asks the model (until `maxAge`), and changed
/// data waits at least `minInterval` since the last request — so a burst of
/// events costs one call, not one per poll.
public struct InsightScheduler: Sendable, Equatable {
  private let minInterval: TimeInterval
  private let maxAge: TimeInterval
  private var lastFingerprint: String?
  private var lastRequest: Date?

  public init(minInterval: TimeInterval = 30, maxAge: TimeInterval = 600) {
    self.minInterval = minInterval
    self.maxAge = maxAge
  }

  public func shouldAutoRequest(fingerprint: String, now: Date) -> Bool {
    guard let lastRequest else { return true }
    let elapsed = now.timeIntervalSince(lastRequest)
    if fingerprint == lastFingerprint { return elapsed >= maxAge }
    return elapsed >= minInterval
  }

  public mutating func didRequest(fingerprint: String, now: Date) {
    lastFingerprint = fingerprint
    lastRequest = now
  }

  /// The last request failed: retry after `minInterval` even if the data is
  /// unchanged, instead of holding the data-only fallback for `maxAge`.
  public mutating func didFail() {
    lastFingerprint = nil
  }

  public mutating func reset() {
    lastFingerprint = nil
    lastRequest = nil
  }
}

/// Recent insights keyed by (context fingerprint, question): a repeat phone
/// ask on unchanged data is answered instantly without a model call.
public struct InsightCache: Sendable, Equatable {
  private struct Key: Hashable, Sendable {
    let fingerprint: String
    let question: InsightQuestion
  }

  private let capacity: Int
  private var entries: [Key: MatchInsight] = [:]
  /// Insertion order, oldest first, for eviction.
  private var order: [Key] = []

  public init(capacity: Int = 8) {
    self.capacity = capacity
  }

  public func insight(fingerprint: String, question: InsightQuestion) -> MatchInsight? {
    entries[Key(fingerprint: fingerprint, question: question)]
  }

  public mutating func store(_ insight: MatchInsight, question: InsightQuestion) {
    let key = Key(fingerprint: insight.fingerprint, question: question)
    if entries[key] == nil { order.append(key) }
    entries[key] = insight
    while order.count > capacity {
      entries[order.removeFirst()] = nil
    }
  }

  public mutating func removeAll() {
    entries = [:]
    order = []
  }
}
