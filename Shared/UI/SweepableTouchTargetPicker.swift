import CoreGraphics

/// Deterministic target selection for iOS sweep routing.
///
/// This is intentionally **pure** (no UIKit/SwiftUI dependencies) so we can unit test it
/// without introducing timing- or environment-dependent flakiness.
enum SweepableTouchTargetPicker {
  struct Candidate: Equatable {
    var frame: CGRect
    var isSuppressed: Bool
    var debugLabel: String

    init(frame: CGRect, isSuppressed: Bool, debugLabel: String = "") {
      self.frame = frame
      self.isSuppressed = isSuppressed
      self.debugLabel = debugLabel
    }
  }

  /// Pick the best candidate index for a touch point.
  ///
  /// Selection rules:
  /// - ignore suppressed candidates
  /// - only consider frames containing `point`
  /// - prefer **smallest area** (proxy for "most specific"/frontmost)
  /// - tie-break by **closest center distance** to the touch point (deterministic)
  static func pickIndex(at point: CGPoint, candidates: [Candidate]) -> Int? {
    var best: (idx: Int, area: CGFloat, centerDist2: CGFloat)?

    for (idx, c) in candidates.enumerated() {
      if c.isSuppressed { continue }
      if !c.frame.contains(point) { continue }

      let area = max(0, c.frame.width) * max(0, c.frame.height)
      let cx = c.frame.midX
      let cy = c.frame.midY
      let dx = point.x - cx
      let dy = point.y - cy
      let dist2 = dx * dx + dy * dy

      if let b = best {
        if area < b.area || (area == b.area && dist2 < b.centerDist2) {
          best = (idx, area, dist2)
        }
      } else {
        best = (idx, area, dist2)
      }
    }

    return best?.idx
  }
}
