//
//  BreakerSceneLeverFalls.swift
//  RockYou
//
//  Animation logic for breaker lever returning to locked position.
//

import Foundation
import SwiftUI

/// Manages the smooth animation of the breaker lever returning to locked position (progress → 0).
/// Physics-based: constant acceleration (gravity), velocity-dependent bounces.
/// - Phase 1: Free fall with constant acceleration until reaching locked (0)
/// - Phase 2: First bounce to 1/4 of drop height
/// - Phase 3: Second bounce to 1/2 of first bounce height
@MainActor
final class BreakerLeverFallAnimator {
  // Strong ref so we can reliably invalidate on interruption (new drag, etc.).
  // The run loop retains the timer too, but if we keep only a weak ref we lose the
  // ability to cancel mid-flight because `timer` becomes nil before `stop()`.
  private var timer: Timer?
  private var animationStartTime: Date?
  private var onUpdate: ((CGFloat) -> Void)?
  private var onComplete: (() -> Void)?
  private var onBounceImpact: ((Int) -> Void)?  // Called with bounce number (1 or 2)
  private var lastLoggedPhase: Phase? = nil

  // Animation state
  private enum Phase {
    case inertiaRise
    case falling
    case bounce1Up
    case bounce1Down
    case bounce2Up
    case bounce2Down
  }

  private var phase: Phase = .falling
  private var phaseStartTime: Date?
  private var dropHeight: CGFloat = 0  // How far we're falling (initial progress)
  private var bounce1Height: CGFloat = 0  // 1/4 of drop height
  private var bounce2Height: CGFloat = 0  // 1/2 of bounce1 (1/8 of drop)

  // Inertia continuation state (used for "post-release" motion)
  private var inertiaFrom: CGFloat = 0
  private var inertiaTo: CGFloat = 0
  private var inertiaDuration: CGFloat = 0
  private var inertiaAcceleration: CGFloat = 0
  private var inertiaInitialVelocity: CGFloat = 0

  // Physics constants
  private let gravity: CGFloat = 2.5  // Acceleration rate (arbitrary units for feel)
  /// Adds an initial downward velocity so the lever doesn't "hesitate" at the start of the fall.
  /// Units are in "progress per second" (since progress is the animated position space).
  private let initialFallVelocity: CGFloat = 0.25
  private let fps: TimeInterval = 1.0 / 60.0  // 60fps

  /// Runs a short, post-release inertial continuation from `from` to `to` using kinematics:
  /// \(x(t) = x_0 + v_0 t - \frac{1}{2} a t^2\), ending with zero velocity at `t = duration`.
  ///
  /// This intentionally shares the same "time-based kinematic" feel as the falling/bounce code,
  /// and avoids duplicating ad-hoc Task/tween loops in gesture code.
  func startInertialContinuation(
    from: CGFloat,
    to: CGFloat,
    durationSeconds: TimeInterval,
    onUpdate: @escaping (CGFloat) -> Void,
    onComplete: @escaping () -> Void
  ) {
    stop()
    DebugBuild.run {
      Log.debug(
        "BreakerSwitch",
        "🧲 LeverAnim startInertia from=\(String(format: "%.3f", from)) to=\(String(format: "%.3f", to)) dur=\(String(format: "%.3fs", durationSeconds))"
      )
    }

    let d = max(0.0, to - from)
    let duration = max(0.01, CGFloat(durationSeconds))
    guard d > 0 else {
      onUpdate(to)
      onComplete()
      return
    }

    // Choose acceleration so that:
    // - v(t=duration) = 0  => v0 - a*duration = 0 => v0 = a*duration
    // - x(duration) - x0 = d = v0*duration - 0.5*a*duration^2 = 0.5*a*duration^2
    //   => a = 2d / duration^2, v0 = 2d / duration
    let a = (2 * d) / (duration * duration)
    let v0 = a * duration

    phase = .inertiaRise
    phaseStartTime = Date()
    self.onUpdate = onUpdate
    self.onComplete = onComplete
    self.onBounceImpact = nil

    inertiaFrom = from
    inertiaTo = to
    inertiaDuration = duration
    inertiaAcceleration = a
    inertiaInitialVelocity = v0

    startTimerLoop()
  }

  func start(
    from progress: CGFloat,
    onUpdate: @escaping (CGFloat) -> Void,
    onBounceImpact: @escaping (Int) -> Void,
    onComplete: @escaping () -> Void
  ) {
    stop()
    DebugBuild.run {
      Log.debug("BreakerSwitch", "🧲 LeverAnim startFall from=\(String(format: "%.3f", progress))")
    }

    self.dropHeight = progress
    self.bounce1Height = progress * 0.2  // 1/5 of drop height
    self.bounce2Height = bounce1Height * 0.333  // 1/3 of first bounce (1/15 of drop)
    self.phase = .falling
    self.animationStartTime = Date()
    self.phaseStartTime = Date()
    self.onUpdate = onUpdate
    self.onBounceImpact = onBounceImpact
    self.onComplete = onComplete

    startTimerLoop()
  }

  func stop() {
    DebugBuild.run {
      Log.debug(
        "BreakerSwitch",
        "🧲 LeverAnim stop timerNil=\(timer == nil ? "true" : "false") phase=\(String(describing: lastLoggedPhase ?? phase))"
      )
    }
    timer?.invalidate()
    timer = nil
    animationStartTime = nil
    phaseStartTime = nil
    lastLoggedPhase = nil
  }

  private func startTimerLoop() {
    // Schedule timer on main run loop (already on main actor)
    let newTimer = Timer(timeInterval: fps, repeats: true) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.tick()
      }
    }
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
    DebugBuild.run {
      Log.debug("BreakerSwitch", "🧲 LeverAnim timerStarted phase=\(String(describing: phase))")
    }
  }

  private func tick() {
    guard let phaseStart = phaseStartTime else { return }

    let phaseElapsed = CGFloat(Date().timeIntervalSince(phaseStart))
    if lastLoggedPhase != phase {
      lastLoggedPhase = phase
      DebugBuild.run {
        Log.debug("BreakerSwitch", "🧲 LeverAnim phase=\(String(describing: phase))")
      }
    }

    switch phase {
    case .inertiaRise:
      let t = min(phaseElapsed, inertiaDuration)
      // x(t) = x0 + v0*t - 0.5*a*t^2
      let position =
        inertiaFrom
        + (inertiaInitialVelocity * t)
        - (0.5 * inertiaAcceleration * t * t)

      if phaseElapsed >= inertiaDuration {
        onUpdate?(inertiaTo)
        // IMPORTANT: Stop the current timer BEFORE invoking onComplete.
        // Callers may start a new animation from onComplete, and `stop()` would otherwise
        // cancel the newly-started timer (leaving the lever "hovering" forever).
        let complete = onComplete
        stop()
        complete?()
      } else {
        onUpdate?(min(inertiaTo, position))
      }

    case .falling:
      // Free fall with initial velocity:
      // position = dropHeight - v0 * t - 0.5 * g * t^2
      let fallDistance =
        (initialFallVelocity * phaseElapsed)
        + (0.5 * gravity * phaseElapsed * phaseElapsed)
      let position = dropHeight - fallDistance

      if position <= 0 {
        // Hit locked position, transition to first bounce
        onUpdate?(0)
        phase = .bounce1Up
        phaseStartTime = Date()
      } else {
        onUpdate?(position)
      }

    case .bounce1Up:
      // Bounce up: position = 0.5 * g * t^2 (rising from 0)
      let riseDistance = 0.5 * gravity * phaseElapsed * phaseElapsed
      let position = min(riseDistance, bounce1Height)

      if position >= bounce1Height {
        // Reached peak, start falling
        onUpdate?(bounce1Height)
        phase = .bounce1Down
        phaseStartTime = Date()
      } else {
        onUpdate?(position)
      }

    case .bounce1Down:
      // Fall from bounce peak: position = bounce1Height - 0.5 * g * t^2
      let fallDistance = 0.5 * gravity * phaseElapsed * phaseElapsed
      let position = bounce1Height - fallDistance

      if position <= 0 {
        // Hit locked position, transition to second bounce
        onUpdate?(0)
        onBounceImpact?(1)  // First bounce impact - strong!
        phase = .bounce2Up
        phaseStartTime = Date()
      } else  {
        onUpdate?(position)
      }

    case .bounce2Up:
      // Second bounce up: position = 0.5 * g * t^2
      let riseDistance = 0.5 * gravity * phaseElapsed * phaseElapsed
      let position = min(riseDistance, bounce2Height)

      if position >= bounce2Height {
        // Reached peak, start falling
        onUpdate?(bounce2Height)
        phase = .bounce2Down
        phaseStartTime = Date()
      } else {
        onUpdate?(position)
      }

    case .bounce2Down:
      // Fall from second bounce: position = bounce2Height - 0.5 * g * t^2
      let fallDistance = 0.5 * gravity * phaseElapsed * phaseElapsed
      let position = bounce2Height - fallDistance

      if position <= 0 {
        // Animation complete
        onUpdate?(0)
        onBounceImpact?(2)  // Second bounce impact - softer
        let complete = onComplete
        stop()
        complete?()
      } else {
        onUpdate?(position)
      }
    }
  }
}
