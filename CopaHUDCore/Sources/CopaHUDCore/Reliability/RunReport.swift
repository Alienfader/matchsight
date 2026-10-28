import Foundation

/// Counts from a captured device console log, for the reliability run.
/// Reads only the `[CopaHUD] …` lines `dbg()` prints; everything else in
/// the console is ignored. The founder's anti-goals lead the summary:
/// the glasses disconnecting, and showing the wrong match.
public struct RunReport: Sendable, Equatable {
  public var sessionStarts = 0
  /// `session state → stopped`: the glasses session ended, for any reason.
  public var disconnects = 0
  public var displayStops = 0
  /// Middle-finger pinch: the system back gesture, which exits the app.
  public var backGestures = 0
  public var sessionErrors: [String: Int] = [:]
  public var renderErrors = 0
  public var renderTimeouts = 0
  public var polls = 0
  public var followSwitches = 0
  public var auditChecks = 0
  public var wrongMatchChecks = 0
  /// Runs of consecutive WRONG audit lines: one event per run.
  public var wrongMatchEvents = 0
  /// Distinct findings, in order of first appearance.
  public var wrongMatchReasons: [String] = []

  static let marker = "[CopaHUD] "

  public static func parse(_ text: String) -> RunReport {
    var r = RunReport()
    var inWrongRun = false
    for raw in text.split(whereSeparator: \.isNewline) {
      guard let range = raw.range(of: marker) else { continue }
      let line = raw[range.upperBound...].trimmingCharacters(in: .whitespaces)

      if line == "session state → started" { r.sessionStarts += 1 }
      else if line == "session state → stopped" { r.disconnects += 1 }
      else if line == "display state → stopped" { r.displayStops += 1 }
      else if line == "input → back (system gesture)" { r.backGestures += 1 }
      else if line.hasPrefix("session error: ") {
        r.sessionErrors[String(line.dropFirst("session error: ".count)), default: 0] += 1
      } else if line.hasPrefix("render error: ") {
        r.renderErrors += 1
        if line.localizedCaseInsensitiveContains("timed out") { r.renderTimeouts += 1 }
      } else if line.hasPrefix("poll ") { r.polls += 1 }
      else if line.hasPrefix("follow: auto → ") { r.followSwitches += 1 }
      else if line.hasPrefix("audit: ok") {
        r.auditChecks += 1
        inWrongRun = false
      } else if line.hasPrefix("audit: WRONG") {
        r.auditChecks += 1
        r.wrongMatchChecks += 1
        if !inWrongRun { r.wrongMatchEvents += 1 }
        inWrongRun = true
        // "audit: WRONG followed=<id> <finding> <finding>…"
        for reason in line.split(separator: " ").dropFirst(3).map(String.init)
        where !r.wrongMatchReasons.contains(reason) {
          r.wrongMatchReasons.append(reason)
        }
      }
    }
    return r
  }

  public var summary: String {
    func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    var lines = [
      "Anti-goals: \(plural(disconnects, "disconnect")), \(plural(wrongMatchEvents, "wrong-match event"))",
      "",
      "Session starts: \(sessionStarts)",
      "Disconnects (session stopped): \(disconnects)",
      "Display stopped: \(displayStops)",
      "Back gestures (exit the app): \(backGestures)",
    ]
    if !sessionErrors.isEmpty {
      let parts = sessionErrors.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }
      lines.append("Session errors: " + parts.joined(separator: ", "))
    }
    lines.append("Render errors: \(renderErrors) (display timeouts: \(renderTimeouts))")
    lines.append("Match polls: \(polls) · auto-follow switches: \(followSwitches)")
    if auditChecks == 0 {
      lines.append("No audit lines: this log is from a build without FollowAudit, or nothing was followed.")
    } else {
      lines.append("Follow audits: \(auditChecks) checks, \(wrongMatchChecks) WRONG")
      if !wrongMatchReasons.isEmpty {
        lines.append("Wrong-match findings: " + wrongMatchReasons.joined(separator: ", "))
      }
    }
    return lines.joined(separator: "\n")
  }
}
