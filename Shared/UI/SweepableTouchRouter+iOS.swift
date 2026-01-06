//
//  SweepableTouchRouter+iOS.swift
//  RockYou (Shared)
//
//  iOS/iPadOS: Centralizes touch observation for all `.sweepable()` views by
//  installing a single non-cancelling recognizer on the window and routing
//  events to the topmost sweepable target under the touch.
//

import SwiftUI
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

  /// Blocking zones: rectangles where touches should NOT route to sweepables.
  /// Used for overlay UI (e.g., keyboard input bar) that should absorb touches.
  private var blockingZones: [ObjectIdentifier: CGRect] = [:]

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

  /// Register a blocking zone that prevents sweepable touches from routing through it.
  func registerBlockingZone(id: ObjectIdentifier, frame: CGRect) {
    blockingZones[id] = frame
  }

  /// Unregister a blocking zone.
  func unregisterBlockingZone(id: ObjectIdentifier) {
    blockingZones.removeValue(forKey: id)
  }

  /// Check if a point is inside any blocking zone.
  private func isBlocked(at point: CGPoint) -> Bool {
    for (_, frame) in blockingZones {
      if frame.contains(point) {
        return true
      }
    }
    return false
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
      if let activeTarget {
        // Match UIKit "touchUpInside" semantics more closely:
        // a quick press/release should only fire if the finger lifts inside the original control.
        let inside = activeTarget.sweepableFrame.contains(point)
        activeTarget.sweepableTouchEnded(cancelled: !inside)
      }
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
    // Check blocking zones first - these absorb touches without routing to any sweepable.
    if isBlocked(at: point) {
      return nil
    }

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

// MARK: - SwiftUI modifier for blocking zones

/// View modifier that registers a blocking zone to prevent sweepable gestures from passing through.
private struct SweepBlockingZoneModifier: ViewModifier {
  @State private var zoneId = UUID()

  func body(content: Content) -> some View {
    content
      .background(
        GeometryReader { proxy in
          Color.clear
            .onAppear {
              if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
              {
                let frame = proxy.frame(in: .global)
                SweepableTouchRouter.shared(for: window)
                  .registerBlockingZone(id: ObjectIdentifier(zoneId as AnyObject), frame: frame)
              }
            }
            .onDisappear {
              if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
              {
                SweepableTouchRouter.shared(for: window)
                  .unregisterBlockingZone(id: ObjectIdentifier(zoneId as AnyObject))
              }
            }
            .onChange(of: proxy.frame(in: .global)) { _, newFrame in
              if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
              {
                SweepableTouchRouter.shared(for: window)
                  .registerBlockingZone(id: ObjectIdentifier(zoneId as AnyObject), frame: newFrame)
              }
            }
        }
      )
  }
}

extension View {
  /// Marks this view as a "blocking zone" that absorbs sweepable gestures.
  /// Touches on this view will not route to sweepable buttons behind it.
  func sweepBlockingZone() -> some View {
    modifier(SweepBlockingZoneModifier())
  }
}
