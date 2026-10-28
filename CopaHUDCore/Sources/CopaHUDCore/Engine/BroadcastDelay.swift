import Foundation

/// The TV delay (Settings): live data often reaches the phone before the TV
/// picture, so the glasses would show a goal before the fan sees it. Feed
/// updates queue here with their arrival time and leave, in order, once
/// `seconds` have passed. Changing `seconds` applies to what is queued.
public struct BroadcastDelay<Item> {
  public static var maxSeconds: TimeInterval { 60 }

  public var seconds: TimeInterval {
    didSet { seconds = Self.clamp(seconds) }
  }
  private var queue: [(at: Date, item: Item)] = []

  public init(seconds: TimeInterval = 0) {
    self.seconds = Self.clamp(seconds)
  }

  public var isEmpty: Bool { queue.isEmpty }

  public mutating func push(_ item: Item, at now: Date) {
    queue.append((now, item))
  }

  /// Everything whose wait is over, oldest first.
  public mutating func due(now: Date) -> [Item] {
    let ready = queue.prefix { now.timeIntervalSince($0.at) >= seconds }
    queue.removeFirst(ready.count)
    return ready.map(\.item)
  }

  public mutating func clear() { queue.removeAll() }

  private static func clamp(_ s: TimeInterval) -> TimeInterval { min(maxSeconds, max(0, s)) }
}
