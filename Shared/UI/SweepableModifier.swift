//
//  SweepableModifier.swift
//  RockYou (Shared)
//
//  ViewModifier that adds hold-to-confirm sweep behavior to any view.
//  Shows fullscreen sweep animation, fires onSweepComplete when held long enough.
//  If released early and no onQuickTap handler, shows tooltip.
//

import SwiftUI

// MARK: - Environment: Sweep Suppression
//
// Used to suppress sweep/tap tooltip side-effects while a parent scroll gesture is active
// (e.g., AppStrip scrolling).

private struct SweepSuppressedKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  var sweepSuppressed: Bool {
    get { self[SweepSuppressedKey.self] }
    set { self[SweepSuppressedKey.self] = newValue }
  }
}

// MARK: - Environment: Sweep Press State
//
// Used by views that render their own chrome (e.g. material buttons) but rely on `.sweepable()`
// for interaction. This lets the chrome animate exactly with the press lifecycle.
private struct SweepPressedKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  var sweepPressed: Bool {
    get { self[SweepPressedKey.self] }
    set { self[SweepPressedKey.self] = newValue }
  }
}

// MARK: - Sweepable Modifier

enum SweepQuickTapPolicy {
  /// Fire `onQuickTap` for any non-completed press (current behavior).
  case anyReleaseBeforeComplete
  /// Fire `onQuickTap` only if the sweep overlay never became visible.
  /// (Useful when a long-press has different semantics than a tap.)
  case onlyIfOverlayNotShown
}

struct SweepableModifier: ViewModifier {
  let iconProvider: () -> SweepOverlayIcon
  let color: Color
  let delay: TimeInterval
  let overlayDelay: UInt64
  let completionHold: UInt64
  let tooltip: String
  /// Debug-only label that helps correlate logs to a specific UI element/app.
  /// Safe to pass in release builds (it is just a string).
  let debugName: String
  /// Called immediately when a press begins (before starting the sweep timer).
  /// Use this to snapshot any dynamic state (e.g. “app at slot index”) so the sweep
  /// uses a consistent target even if the underlying list changes mid-hold.
  let onPressBegan: (() -> Void)?
  let quickTapPolicy: SweepQuickTapPolicy
  let onQuickTap: (() -> Void)?
  let onSweepComplete: () -> Void

  @State private var machine = SweepPressStateMachine(
    config: .init(
      delay: 1.0,
      overlayDelay: 0.1,
      cancelDistanceInitial: 12,
      cancelDistanceLocked: 24,
      hasQuickTapHandler: false,
      quickTapPolicy: .anyReleaseBeforeComplete,
      tooltipEmissionPolicy: .always,
      tooltipText: ""
    )
  )
  @State private var sweepTask: Task<Void, Never>?
  @State private var buttonFrame: CGRect = .zero
  @State private var pressToken: UInt64 = 0

  // MARK: - Cancel distance tuning
  //
  // Shared rule across platforms:
  // - The "tentative" phase (before the overlay shows) is the only place that contends with
  //   scroll/pan gestures, so it stays tight: a platform-tuned baseline with a tiny bit of wiggle.
  // - Once we've committed to a hold (overlay shown) the overlay is modal — the source button's
  //   frame no longer matters, and scroll is no longer a plausible intent — so we can be generous.
  //   We use a flat, absolute distance here rather than scaling the (scroll-tuned) baseline.
  //
  // Note: On platforms where we rely on SwiftUI's `onLongPressGesture(maximumDistance:)`,
  // we only get one threshold, so we use the "initial" phase there.
  private enum SweepCancelTuning {
    static let initialMultiplier: CGFloat = 1.10  // "tiny bit bigger"
    static let lockedDistance: CGFloat = 32  // absolute slop once committed (touch-router path)
  }

  // Baseline distance (used by the touch-router path).
  @MainActor
  private var cancelDistance: CGFloat { SweepableModifierPlatform.baseCancelDistance }
  // Threshold used by the SwiftUI long-press path and for the "tentative" phase.
  @MainActor
  private var cancelDistanceInitial: CGFloat {
    SweepableModifierPlatform.baseCancelDistance * SweepCancelTuning.initialMultiplier
  }
  // Threshold used by the "committed" phase (touch-router path only).
  @MainActor
  private var cancelDistanceLocked: CGFloat {
    SweepCancelTuning.lockedDistance
  }

  private var sweepManager: SweepManager { SweepManager.shared }
  @Environment(\.sweepSuppressed) private var sweepSuppressed
  @Environment(\.isEnabled) private var isEnabled

  /// Sweepables should behave like normal controls: when disabled, they must not begin a press,
  /// must not show the sweep overlay, and must not fire quick-tap/sweep actions.
  private var effectiveSuppressed: Bool { sweepSuppressed || !isEnabled }

  func body(content: Content) -> some View {
    let base =
      content
      .background(
        GeometryReader { geo in
          Color.clear
            .onAppear { buttonFrame = geo.frame(in: .global) }
            .onChange(of: geo.frame(in: .global)) { _, newFrame in buttonFrame = newFrame }
        }
      )

    return
      SweepableModifierPlatform.attachGestureDriver(
        base: base,
        buttonFrame: buttonFrame,
        sweepSuppressed: effectiveSuppressed,
        debugLabel: debugLabel,
        pressToken: pressToken,
        delay: delay,
        cancelDistanceInitial: cancelDistanceInitial,
        tooltip: tooltip,
        hasQuickTapHandler: onQuickTap != nil,
        machineDidComplete: machine.didComplete,
        overlayIsShowing: sweepManager.isShowing,
        onBegan: {
          Log.debug("Sweep", "\(debugLabel) began token=\(pressToken)")
          handleTouchBegan()
        },
        onMoved: { distance in
          handleTouchMoved(distance: distance)
        },
        onEnded: { cancelled in
          Log.debug("Sweep", "\(debugLabel) ended(cancelled=\(cancelled)) token=\(pressToken)")
          handleTouchEnded(wasCancelled: cancelled)
        },
        onCompleteRequested: {
          let now = ProcessInfo.processInfo.systemUptime
          _ = apply(machine.completeRequested(now: now), now: now)
        }
      )
      .environment(\.sweepPressed, machine.isPressed)
      .onChange(of: sweepSuppressed) { _, _ in
        DebugBuild.run {
          Log.gestureTimeline(
            "Sweep",
            "suppressedChanged",
            [
              "label": debugLabel,
              "suppressed": effectiveSuppressed ? "true" : "false",
            ]
          )
        }
        let now = ProcessInfo.processInfo.systemUptime
        _ = apply(machine.setSuppressed(effectiveSuppressed, now: now), now: now)
      }
      .onChange(of: isEnabled) { _, _ in
        DebugBuild.run {
          Log.gestureTimeline(
            "Sweep",
            "enabledChanged",
            [
              "label": debugLabel,
              "enabled": isEnabled ? "true" : "false",
              "suppressed": effectiveSuppressed ? "true" : "false",
            ]
          )
        }
        let now = ProcessInfo.processInfo.systemUptime
        _ = apply(machine.setSuppressed(effectiveSuppressed, now: now), now: now)
      }
      .onDisappear {
        SweepableModifierPlatform.sourceViewDidDisappear()
      }
  }

  // MARK: - Press Handling

  private func handleTouchBegan() {
    if effectiveSuppressed { return }
    Log.gestureTimeline(
      "Sweep",
      "pressBegan",
      ["label": debugLabel, "path": SweepableModifierPlatform.pressBeganPathLabel]
    )
    SweepableModifierPlatform.prepareForPressBegan()
    onPressBegan?()
    startPress()
  }

  private func handleTouchMoved(distance: CGFloat) {
    let now = ProcessInfo.processInfo.systemUptime
    _ = apply(machine.moved(distance: distance, now: now), now: now)
  }

  private func handleTouchEnded(wasCancelled: Bool) {
    let now = ProcessInfo.processInfo.systemUptime
    Log.gestureTimeline(
      "Sweep",
      "pressEnded",
      [
        "label": debugLabel,
        "cancelled": wasCancelled ? "true" : "false",
        "suppressed": sweepSuppressed ? "true" : "false",
      ]
    )
    _ = apply(machine.pressEnded(cancelled: wasCancelled, now: now), now: now)
  }

  private func startPress() {
    let now = ProcessInfo.processInfo.systemUptime
    pressToken &+= 1
    Log.debug(
      "Sweep",
      "\(debugLabel) startPress token=\(pressToken) delay=\(String(format: "%.2f", delay))s"
    )
    machine.updateConfig(currentMachineConfig())
    _ = apply(machine.pressBegan(now: now), now: now)
    guard machine.isPressed else { return }

    // Capture deadlines immediately (we are already on the main actor here).
    // This avoids async MainActor hops from within the task and makes sequencing clearer.
    let overlayAt = machine.overlayDeadline
    let completionAt = machine.completionDeadline

    sweepManager.onCancel = { cancelSweep() }  // cancels current press

    // Drive overlay + progress + completion without depending on SwiftUI gesture ordering.
    sweepTask?.cancel()
    sweepTask = Task {
      // 1) Wait until overlay deadline, then tick the state machine (may show overlay).
      if let overlayAt {
        let tNow = ProcessInfo.processInfo.systemUptime
        let dt = max(0, overlayAt - tNow)
        if dt > 0 {
          try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
        }
      } else {
        // No overlay scheduled (degenerate). Continue.
      }

      guard !Task.isCancelled else { return }
      await MainActor.run {
        let tNow = ProcessInfo.processInfo.systemUptime
        _ = apply(machine.tick(now: tNow), now: tNow)
      }

      // 2) Animate sweep progress until completion deadline (or cancellation).
      let steps = 90
      let startNow = ProcessInfo.processInfo.systemUptime
      let remaining = max(0, (completionAt ?? startNow) - startNow)
      let stepDuration = remaining > 0 ? UInt64((remaining / Double(steps)) * 1_000_000_000) : 0

      if stepDuration > 0 {
        for i in 1...steps {
          try? await Task.sleep(nanoseconds: stepDuration)
          guard !Task.isCancelled else { return }
          await MainActor.run {
            guard machine.isPressed else { return }
            sweepManager.updateProgress(CGFloat(i) / CGFloat(steps))
            if i % 25 == 0 {
              HapticService.play(.click)
            }
          }
        }
      }

      // 3) Timer-based completion fallback (matches the prior behavior).
      await MainActor.run {
        let now = ProcessInfo.processInfo.systemUptime
        Log.gestureTimeline("Sweep", "timerComplete", ["label": debugLabel])
        _ = apply(machine.tick(now: now), now: now)
      }
    }
  }

  private func cancelSweep() {
    Log.debug("Sweep", "\(debugLabel) cancelSweep token=\(pressToken)")
    Log.gestureTimeline("Sweep", "cancelSweep", ["label": debugLabel])
    let now = ProcessInfo.processInfo.systemUptime
    _ = apply(machine.pressEnded(cancelled: true, now: now), now: now)
  }

  @discardableResult
  private func apply(_ actions: [SweepPressStateMachine.Action], now: TimeInterval)
    -> [SweepPressStateMachine.Action]
  {
    guard !actions.isEmpty else { return actions }

    for action in actions {
      switch action {
      case .pressedChanged:
        break

      case .endCleanup:
        sweepTask?.cancel()
        sweepTask = nil
        sweepManager.dismiss()

      case .overlayShown:
        Log.gestureTimeline("Sweep", "overlayShown", ["label": debugLabel])
        sweepManager.show(icon: iconProvider(), color: color)
        HapticService.play(.start)

      case .completed:
        Log.debug("Sweep", "\(debugLabel) completeSweep firing token=\(pressToken)")
        Log.gestureTimeline("Sweep", "complete", ["label": debugLabel])
        sweepTask?.cancel()
        sweepTask = nil
        HapticService.notifySuccess()
        sweepManager.updateProgress(1)
        Log.debug("Sweep", "\(debugLabel) onSweepComplete() token=\(pressToken)")
        onSweepComplete()
        sweepManager.dismiss(after: Double(completionHold) / 1_000_000_000)

      case .quickTap:
        Log.gestureTimeline("Sweep", "quickTap", ["label": debugLabel, "policy": "\(quickTapPolicy)"])
        if let onQuickTap {
          HapticService.play(.click)
          onQuickTap()
        } else if delay <= 0 {
          // Tap-ish mode: treat quick tap as the primary action.
          onSweepComplete()
        }
        // Overlay/task cleanup is handled by `.endCleanup`.

      case .showTooltip(let reason):
        let event: String = {
          switch reason {
          case .quickAbandonOverlay:
            return "tooltipOnQuickAbandon"
          case .noQuickTapHandler, .quickTapSuppressedByPolicy:
            return "tooltipOnTapRelease"
          }
        }()
        Log.gestureTimeline("Sweep", event, ["label": debugLabel, "reason": "\(reason)"])
        TooltipManager.shared.show(tooltip, buttonFrame: buttonFrame)

      case .cancelled(let reason):
        if case .draggedBeyondThreshold(let distance, let threshold, let locked) = reason {
          Log.gestureTimeline(
            "Sweep",
            "dragCancel",
            [
              "label": debugLabel,
              "distance": Int(distance),
              "threshold": Int(threshold),
              "locked": locked ? "true" : "false",
            ]
          )
        }
        Log.gestureTimeline("Sweep", "cancelled", ["label": debugLabel, "reason": "\(reason)"])
        // Cleanup is handled by `.endCleanup` (which the state machine emits on cancel).
      }
    }

    return actions
  }

  private func currentMachineConfig() -> SweepPressStateMachine.Config {
    let overlayDelaySeconds = Double(overlayDelay) / 1_000_000_000
    let tooltipEmissionPolicy = SweepableModifierPlatform.tooltipEmissionPolicy

    return SweepPressStateMachine.Config(
      delay: delay,
      overlayDelay: overlayDelaySeconds,
      cancelDistanceInitial: cancelDistanceInitial,
      cancelDistanceLocked: cancelDistanceLocked,
      hasQuickTapHandler: onQuickTap != nil,
      quickTapPolicy: quickTapPolicy,
      tooltipEmissionPolicy: tooltipEmissionPolicy,
      tooltipText: tooltip
    )
  }

  private var debugLabel: String {
    let t = tooltip.isEmpty ? "∅" : tooltip
    if debugName.isEmpty {
      return "tooltip='\(t)'"
    }
    return "\(debugName) tooltip='\(t)'"
  }
}

// (View extension moved to `Shared/UI/Platform/SweepableModifier+nonMac.swift`)
