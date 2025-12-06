//
//  SweepableTouchRouter+iOS.swift
//  RockYou (Shared)
//
//  iOS/iPadOS: Centralizes touch observation for all `.sweepable()` views by
//  installing a single non-cancelling recognizer on the window and routing
//  events to the topmost sweepable target under the touch.
//

import UIKit

@MainActor
protocol SweepableTouchTarget: AnyObject {
  var sweepableFrame: CGRect { get }
  var sweepableSuppressed: Bool { get }
  var sweepableDebugLabel: String { get }

  func sweepableTouchBegan()
  func sweepableTouchMoved(distance: CGFloat)
  func sweepableTouchEnded(cancelled: Bool)
}

@MainActor
final class SweepableTouchRouter: NSObject, UIGestureRecognizerDelegate {
  private static var routersByWindow: [ObjectIdentifier: SweepableTouchRouter] = [:]

  static func shared(for window: UIWindow) -> SweepableTouchRouter {
    let key = ObjectIdentifier(window)
    if let existing = routersByWindow[key] {
      return existing
    }
    let router = SweepableTouchRouter(window: window)
    routersByWindow[key] = router
    return router
  }

  private weak var window: UIWindow?
  private let targets = NSHashTable<AnyObject>.weakObjects()

  private var activeTarget: SweepableTouchTarget?
  private var startPoint: CGPoint = .zero

  private init(window: UIWindow) {
    self.window = window
    super.init()
    installRecognizer(on: window)
  }

  func register(_ target: SweepableTouchTarget) {
    targets.add(target)
  }

  func unregister(_ target: SweepableTouchTarget) {
    targets.remove(target)
    if activeTarget === target {
      activeTarget = nil
    }
  }

  // MARK: - Gesture recognizer

  private let recognizerName = "SweepableTouchRouter"

  private func installRecognizer(on window: UIWindow) {
    if let existing = window.gestureRecognizers?.first(where: { $0.name == recognizerName }) as? UILongPressGestureRecognizer {
      existing.addTarget(self, action: #selector(handle(_:)))
      return
    }

    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
    recognizer.name = recognizerName
    recognizer.minimumPressDuration = 0
    recognizer.allowableMovement = .greatestFiniteMagnitude
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = self

    window.addGestureRecognizer(recognizer)
  }

  @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
    // Prefer the recognizer's view window when possible (more robust if our stored reference
    // becomes stale due to scene/window churn).
    guard let window = (recognizer.view as? UIWindow) ?? window else { return }
    let point = recognizer.location(in: window)

    switch recognizer.state {
    case .began:
      // Debug-only instrumentation: used to compare refactors without UI automation.
      Log.gestureTimeline(
        "SweepRouter",
        "began",
        [
          "x": Int(point.x),
          "y": Int(point.y),
          "targets": targets.allObjects.count,
          "tooltipVisible": TooltipManager.shared.message != nil ? "true" : "false",
          "sweepOverlayShowing": SweepManager.shared.isShowing ? "true" : "false",
        ]
      )

      // Tooltip dismissal on touch-down (iOS):
      // Tooltips are rendered in a separate pass-through window; if we receive this touch in the
      // app window, it is necessarily outside the bubble, so we can dismiss.
      if TooltipManager.shared.message != nil {
        // Important: schedule dismissal for the next runloop tick so we don't mutate SwiftUI
        // view state *during* touch dispatch (which can derail the underlying gesture).
        DispatchQueue.main.async {
          Task { @MainActor in
            TooltipManager.shared.dismiss(immediately: true)
          }
        }
      }

      // Sweep overlay is modal: treat touches as overlay interactions only.
      if SweepManager.shared.isShowing {
        activeTarget = nil
        return
      }

      startPoint = point
      activeTarget = pickTarget(at: point)
      activeTarget?.sweepableTouchBegan()

    case .changed:
      guard let activeTarget else { return }
      let dx = point.x - startPoint.x
      let dy = point.y - startPoint.y
      let dist = sqrt(dx * dx + dy * dy)
      Log.gestureTimeline(
        "SweepRouter",
        "moved",
        [
          "distance": Int(dist),
          "target": activeTarget.sweepableDebugLabel,
        ]
      )
      activeTarget.sweepableTouchMoved(distance: dist)

    case .ended:
      Log.gestureTimeline(
        "SweepRouter",
        "ended",
        [
          "target": activeTarget?.sweepableDebugLabel ?? "nil",
        ]
      )
      activeTarget?.sweepableTouchEnded(cancelled: false)
      activeTarget = nil

    case .cancelled, .failed:
      Log.gestureTimeline(
        "SweepRouter",
        "cancelled",
        [
          "target": activeTarget?.sweepableDebugLabel ?? "nil",
        ]
      )
      activeTarget?.sweepableTouchEnded(cancelled: true)
      activeTarget = nil

    default:
      break
    }
  }

  private func pickTarget(at point: CGPoint) -> SweepableTouchTarget? {
    let candidates: [SweepableTouchTarget] = targets.allObjects.compactMap { $0 as? SweepableTouchTarget }

    // Make selection deterministic without relying on NSHashTable iteration order.
    let snapshots = candidates.map {
      SweepableTouchTargetPicker.Candidate(
        frame: $0.sweepableFrame,
        isSuppressed: $0.sweepableSuppressed,
        debugLabel: $0.sweepableDebugLabel
      )
    }

    guard let idx = SweepableTouchTargetPicker.pickIndex(at: point, candidates: snapshots) else {
      return nil
    }
    return candidates[idx]
  }

  // MARK: - UIGestureRecognizerDelegate

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    // Critical for iOS: allow the window-level observer recognizer to run alongside
    // ScrollView pan and other gestures, otherwise `.sweepable()` becomes inert.
    _ = gestureRecognizer
    _ = otherGestureRecognizer
    return true
  }
}
