import Foundation

/// What the insight page and the phone's analyst card show right now.
public struct InsightState: Sendable, Equatable {
  public var insight: MatchInsight?
  public var question: InsightQuestion?
  /// A request is in flight (the glasses footer shows "updating…").
  public var isUpdating: Bool
  /// Why the last answer fell back to the template; phone-only detail.
  public var lastError: InsightError?
  /// The context behind the request was demo data.
  public var isScripted: Bool

  public static let idle = InsightState(insight: nil, question: nil, isUpdating: false,
                                        lastError: nil, isScripted: false)

  public init(insight: MatchInsight?, question: InsightQuestion?, isUpdating: Bool,
              lastError: InsightError?, isScripted: Bool) {
    self.insight = insight
    self.question = question
    self.isUpdating = isUpdating
    self.lastError = lastError
    self.isScripted = isScripted
  }

  /// The glasses page content, or nil before the first insight ("warming up").
  /// Footer says honestly where the words came from.
  public var hudContent: InsightContent? {
    guard let insight else { return nil }
    var parts: [String]
    switch insight.source {
    case .model: parts = ["Muse Spark", Self.basisLabel(insight.basis)]
    case .template: parts = ["Data only"]
    case .mock: parts = ["Mock AI"]
    }
    if isScripted { parts.append("scripted") }
    if isUpdating { parts.append("updating…") }
    return InsightContent(title: insight.title, body: insight.body,
                          footer: parts.joined(separator: " · "))
  }

  private static func basisLabel(_ basis: InsightBasis) -> String {
    switch basis {
    case .observed: return "observed"
    case .dataInference: return "inferred"
    case .generalTactics: return "general"
    }
  }
}

/// Owns every model call: decides when to auto-refresh, lets a phone ask win
/// over a running refresh, serves repeats from the cache, and turns any
/// failure into the data-only template. Requests run on cancellable Tasks so
/// nothing here ever blocks rendering or tap handling.
@MainActor
public final class InsightCoordinator {
  public var onChange: ((InsightState) -> Void)?
  public private(set) var state: InsightState = .idle

  private var service: any MatchInsightService
  private var scheduler: InsightScheduler
  private var cache = InsightCache()
  private let now: () -> Date
  /// The followed match. Contexts for any other fixture (e.g. from a poll
  /// loop that was cancelled mid-await) are ignored. Nil → ignore all.
  private var fixtureId: Int?
  /// In-flight request; internal so tests can await it.
  private(set) var currentTask: Task<Void, Never>?
  /// Bumped whenever a request is superseded; stale results are dropped.
  private var generation = 0

  public init(service: any MatchInsightService, scheduler: InsightScheduler = InsightScheduler(),
              now: @escaping () -> Date = Date.init) {
    self.service = service
    self.scheduler = scheduler
    self.now = now
  }

  /// Swap the model backend (key entered/removed). Cached answers came from
  /// the old backend, so they go too.
  public func setService(_ service: any MatchInsightService) {
    cancelInFlight()
    self.service = service
    cache.removeAll()
    scheduler.reset()
    if state.isUpdating || state.lastError == .unauthorized {
      state.isUpdating = false
      state.lastError = nil
      publish()
    }
  }

  /// Auto refresh after a poll. Skipped while a request runs, after a
  /// rejected key, or when the scheduler says the data hasn't meaningfully
  /// changed.
  public func contextChanged(_ context: MatchInsightContext) {
    // A rejected key won't fix itself: pause auto refresh until the backend
    // changes (setService) instead of failing on every poll.
    guard context.fixtureId == fixtureId, currentTask == nil,
          state.lastError != .unauthorized,
          scheduler.shouldAutoRequest(fingerprint: context.fingerprint, now: now()) else { return }
    scheduler.didRequest(fingerprint: context.fingerprint, now: now())
    run(.matchStory, context: context)
  }

  /// Phone-side "Ask the analyst": answered from cache when the data is
  /// unchanged, otherwise cancels any running request and asks the model.
  public func ask(_ question: InsightQuestion, context: MatchInsightContext) {
    guard context.fixtureId == fixtureId else { return }
    cancelInFlight()
    // A manual answer counts as a request, so the next poll's auto refresh
    // doesn't replace what the user just asked for within `minInterval`.
    scheduler.didRequest(fingerprint: context.fingerprint, now: now())
    if let cached = cache.insight(fingerprint: context.fingerprint, question: question) {
      state.insight = cached
      state.question = question
      state.isUpdating = false
      state.lastError = nil
      state.isScripted = context.isScripted
      publish()
      return
    }
    run(question, context: context)
  }

  /// Followed match changed / unfollowed (nil): drop everything, including
  /// any answer still in flight for the old match, and accept only contexts
  /// for `fixtureId` from now on.
  public func reset(fixtureId: Int?) {
    self.fixtureId = fixtureId
    cancelInFlight()
    cache.removeAll()
    scheduler.reset()
    state = .idle
    publish()
  }

  // MARK: - Requests

  private func cancelInFlight() {
    currentTask?.cancel()
    currentTask = nil
    generation += 1
  }

  private func run(_ question: InsightQuestion, context: MatchInsightContext) {
    generation += 1
    let gen = generation
    state.isUpdating = true
    state.isScripted = context.isScripted
    publish()

    let service = self.service
    currentTask = Task { [weak self] in
      let outcome: Result<MatchInsight, Error>
      do {
        outcome = .success(try await service.insight(for: context, question: question))
      } catch {
        outcome = .failure(error)
      }
      self?.finish(outcome, question: question, context: context, generation: gen)
    }
  }

  private func finish(_ outcome: Result<MatchInsight, Error>, question: InsightQuestion,
                      context: MatchInsightContext, generation gen: Int) {
    guard gen == generation else { return }   // superseded: drop silently
    currentTask = nil
    switch outcome {
    case .success(let insight):
      cache.store(insight, question: question)
      state.insight = insight
      state.lastError = nil
    case .failure(let error) where error is CancellationError:
      state.isUpdating = false
      publish()
      return
    case .failure(let error):
      state.insight = InsightTemplate.make(context: context)
      state.lastError = (error as? InsightError) ?? .network(String(describing: error))
      scheduler.didFail()
    }
    state.question = question
    state.isUpdating = false
    publish()
  }

  private func publish() {
    onChange?(state)
  }
}
