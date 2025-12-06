//
//  SweepPressStateMachine.swift
//  RockYou (Shared)
//
//  Pure, deterministic state machine for the Sweep press lifecycle.
//
//  This intentionally avoids SwiftUI / UIKit types so it can be unit-tested without UI automation.
//

import CoreGraphics
import Foundation

/// Pure sweep press state machine.
///
/// The caller is responsible for:
/// - Providing a clock (`now`) to all calls.
/// - Scheduling `tick(now:)` calls (or calling it opportunistically) to drive overlay and completion.
struct SweepPressStateMachine {
  struct Config: Equatable {
    var delay: TimeInterval
    var overlayDelay: TimeInterval

    var cancelDistanceInitial: CGFloat
    var cancelDistanceLocked: CGFloat

    var hasQuickTapHandler: Bool
    var quickTapPolicy: SweepQuickTapPolicy

    enum TooltipEmissionPolicy: Equatable {
      /// Never emit tooltips from release events.
      case none
      /// Only emit tooltips for the "quick abandon after overlay started" case.
      /// Intended for watchOS where tap tooltips are driven by a dedicated TapGesture,
      /// but we still want the "started then released quickly" guidance.
      case overlayOnly
      /// Emit tooltips for both tap-release and quick-abandon cases.
      case always
    }

    var tooltipEmissionPolicy: TooltipEmissionPolicy
    var tooltipText: String

    init(
      delay: TimeInterval,
      overlayDelay: TimeInterval,
      cancelDistanceInitial: CGFloat,
      cancelDistanceLocked: CGFloat,
      hasQuickTapHandler: Bool,
      quickTapPolicy: SweepQuickTapPolicy,
      tooltipEmissionPolicy: TooltipEmissionPolicy,
      tooltipText: String
    ) {
      self.delay = delay
      self.overlayDelay = overlayDelay
      self.cancelDistanceInitial = cancelDistanceInitial
      self.cancelDistanceLocked = cancelDistanceLocked
      self.hasQuickTapHandler = hasQuickTapHandler
      self.quickTapPolicy = quickTapPolicy
      self.tooltipEmissionPolicy = tooltipEmissionPolicy
      self.tooltipText = tooltipText
    }
  }

  enum TooltipReason: Equatable {
    /// No quick-tap handler exists; release should show tooltip.
    case noQuickTapHandler
    /// Quick-tap handler exists, but policy suppressed quick tap (e.g. overlay was shown).
    case quickTapSuppressedByPolicy
    /// Overlay was visible and released quickly after overlay appeared.
    case quickAbandonOverlay
  }

  enum Action: Equatable {
    case pressedChanged(Bool)
    case overlayShown
    /// Request caller-owned cleanup for any non-completed end-of-press:
    /// cancel timers/tasks, dismiss overlay/progress UI, clear transient visuals.
    case endCleanup
    case cancelled(reason: CancelReason)
    case completed
    case quickTap
    case showTooltip(reason: TooltipReason)
  }

  enum CancelReason: Equatable {
    case systemCancelled
    case draggedBeyondThreshold(distance: CGFloat, threshold: CGFloat, locked: Bool)
    case suppressed
  }

  private(set) var config: Config

  private(set) var isPressed: Bool = false
  private(set) var isSuppressed: Bool = false
  private(set) var didComplete: Bool = false
  private(set) var didDragCancel: Bool = false

  private(set) var pressBeganAt: TimeInterval = 0
  private(set) var overlayBeganAt: TimeInterval?
  private(set) var overlayVisible: Bool = false

  private var overlayAt: TimeInterval?
  private var completeAt: TimeInterval?

  init(config: Config) {
    self.config = config
  }

  mutating func updateConfig(_ newConfig: Config) {
    config = newConfig
  }

  var overlayDeadline: TimeInterval? { overlayAt }
  var completionDeadline: TimeInterval? { completeAt }

  // MARK: - External events

  mutating func setSuppressed(_ suppressed: Bool, now: TimeInterval) -> [Action] {
    let was = isSuppressed
    isSuppressed = suppressed
    guard suppressed, suppressed != was else { return [] }
    guard isPressed, !didComplete else { return [] }
    didDragCancel = true
    return cancel(now: now, reason: .suppressed)
  }

  mutating func pressBegan(now: TimeInterval) -> [Action] {
    guard !isSuppressed else { return [] }
    guard !isPressed else { return [] }
    resetPressState()
    isPressed = true
    pressBeganAt = now
    overlayAt = now + max(0, config.overlayDelay)
    completeAt = now + max(0, config.delay)
    return [.pressedChanged(true)]
  }

  mutating func moved(distance: CGFloat, now: TimeInterval) -> [Action] {
    guard isPressed, !didComplete, !didDragCancel else { return [] }
    let locked = overlayVisible
    let threshold = locked ? config.cancelDistanceLocked : config.cancelDistanceInitial
    guard distance > threshold else { return [] }
    didDragCancel = true
    return cancel(
      now: now,
      reason: .draggedBeyondThreshold(distance: distance, threshold: threshold, locked: locked)
    )
  }

  mutating func pressEnded(cancelled: Bool, now: TimeInterval) -> [Action] {
    guard isPressed else { return [] }
    guard !didComplete else { return [] }

    if cancelled || didDragCancel || isSuppressed {
      return cancel(
        now: now,
        reason: cancelled ? .systemCancelled : (isSuppressed ? .suppressed : .systemCancelled)
      )
    }

    // End press normally.
    isPressed = false
    let actions: [Action] = [.pressedChanged(false)] + endActions(now: now)
    clearDeadlines()
    return actions
  }

  /// Explicit completion request (e.g. SwiftUI `onLongPressGesture(perform:)`).
  mutating func completeRequested(now: TimeInterval) -> [Action] {
    guard isPressed, !didComplete else { return [] }
    didComplete = true
    isPressed = false
    clearDeadlines()
    return [.completed, .pressedChanged(false)]
  }

  // MARK: - Timer driving

  /// Drive deadlines (overlay and completion). The caller should call this via scheduled timers
  /// or at natural points (e.g. in a Task loop) using a deterministic clock in tests.
  mutating func tick(now: TimeInterval) -> [Action] {
    guard isPressed, !didComplete, !didDragCancel, !isSuppressed else { return [] }
    var out: [Action] = []

    if let overlayAt, !overlayVisible, now >= overlayAt {
      overlayVisible = true
      overlayBeganAt = now
      out.append(.overlayShown)
    }

    if let completeAt, now >= completeAt {
      // Timer-based completion fallback.
      out.append(contentsOf: completeRequested(now: now))
    }

    return out
  }

  // MARK: - Internals

  private mutating func resetPressState() {
    didComplete = false
    didDragCancel = false
    overlayVisible = false
    overlayBeganAt = nil
    pressBeganAt = 0
  }

  private mutating func clearDeadlines() {
    overlayAt = nil
    completeAt = nil
  }

  private mutating func cancel(now: TimeInterval, reason: CancelReason) -> [Action] {
    isPressed = false
    clearDeadlines()
    // Ensure callers cleanup any in-flight sweep task / overlay state on cancellation.
    return [.cancelled(reason: reason), .pressedChanged(false), .endCleanup]
  }

  private mutating func endActions(now: TimeInterval) -> [Action] {
    // Always request cleanup on non-completed release (even if no tooltip is shown).
    var out: [Action] = [.endCleanup]

    // Quick-tap path.
    if config.hasQuickTapHandler {
      if config.quickTapPolicy == .onlyIfOverlayNotShown, overlayVisible {
        // Fall through to tooltip logic (if enabled).
      } else {
        out.append(.quickTap)
        return out
      }
    }

    // Tooltip path (release-driven platforms only).
    guard config.tooltipEmissionPolicy != .none else { return out }
    guard !config.tooltipText.isEmpty else { return out }
    guard !isSuppressed else { return out }

    if overlayVisible, let overlayBeganAt {
      let overlayElapsed = now - overlayBeganAt
      let threshold = max(config.delay / 2.0, 0.5)
      if overlayElapsed < threshold {
        out.append(.showTooltip(reason: .quickAbandonOverlay))
        return out
      }
      return out
    }

    // If we only want the overlay quick-abandon tooltip, do not emit a tooltip on tap-release.
    if config.tooltipEmissionPolicy == .overlayOnly {
      return out
    }

    out.append(
      .showTooltip(
        reason: config.hasQuickTapHandler ? .quickTapSuppressedByPolicy : .noQuickTapHandler
      )
    )
    return out
  }
}
