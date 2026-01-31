// DomeAnimationManager.swift
// RockYou/UI/Dome
//
// Shared observable singleton that bridges dome animation state between
// LockableDPadView (trigger, deep in the view hierarchy) and
// ContentViewCore (display, at the root).

import Combine
import SwiftUI

@MainActor
final class DomeAnimationManager: ObservableObject {
  static let shared = DomeAnimationManager()

  @Published private(set) var isActive: Bool = false
  @Published private(set) var openProgress: CGFloat = 0
  @Published private(set) var animationComplete: Bool = false
  @Published var dpadSurfaced: Bool = false

  /// Old dome frame size for viewport scale compensation.
  @Published private(set) var referenceDomeSize: CGFloat = 0

  private var nonce: UInt64 = 0

  private init() {}

  /// Activates the dome animation and drives `openProgress` from 0 to 1
  /// over `DomeSceneConfig.duration`, then waits a grace period for the
  /// shader to report completion before tearing down.
  func start(referenceDomeSize: CGFloat) {
    nonce &+= 1
    let myNonce = nonce
    let openDurationSeconds = TimeInterval(DomeSceneConfig.duration)
    let hardCapGrace = openDurationSeconds * 0.2
    let frameIntervalSeconds: TimeInterval = 1.0 / 60.0

    withTransaction(Transaction(animation: nil)) {
      isActive = true
      openProgress = 0
      animationComplete = false
      dpadSurfaced = false
      self.referenceDomeSize = referenceDomeSize
    }

    Task { @MainActor in
      Log.debug(
        "DomeDoors",
        "Start dome open: duration=\(String(format: "%.2f", openDurationSeconds))s nonce=\(myNonce)"
      )
      // Allow the dome view to mount before animating progress.
      await Task.yield()
      guard nonce == myNonce else {
        Log.debug("DomeDoors", "Canceled before start: nonce changed")
        return
      }

      let start = Date()
      while nonce == myNonce {
        let elapsed = Date().timeIntervalSince(start)
        let progress = min(1.0, max(0, elapsed / openDurationSeconds))
        openProgress = progress
        if progress >= 1.0 { break }
        try? await Task.sleep(nanoseconds: UInt64(frameIntervalSeconds * 1_000_000_000))
      }

      let elapsedTotal = Date().timeIntervalSince(start)
      if nonce != myNonce {
        Log.debug(
          "DomeDoors",
          "Canceled mid-open: elapsed=\(String(format: "%.2f", elapsedTotal))s nonce=\(myNonce)"
        )
        return
      }

      Log.debug(
        "DomeDoors",
        "Open complete: elapsed=\(String(format: "%.2f", elapsedTotal))s nonce=\(myNonce)"
      )

      // Grace period: wait for shader completion or hard cap.
      let graceStart = Date()
      while nonce == myNonce && !animationComplete {
        let graceElapsed = Date().timeIntervalSince(graceStart)
        if graceElapsed >= hardCapGrace { break }
        try? await Task.sleep(nanoseconds: UInt64(frameIntervalSeconds * 1_000_000_000))
      }

      guard nonce == myNonce else { return }
      let totalElapsed = Date().timeIntervalSince(start)
      Log.debug(
        "DomeDoors",
        "Teardown dome: total=\(String(format: "%.2f", totalElapsed))s complete=\(animationComplete) nonce=\(myNonce)"
      )
      isActive = false
    }
  }

  /// Called by the dome view when the shader reports completion.
  func reportComplete() {
    animationComplete = true
  }

  /// Cancels any running dome animation and resets all state.
  func cancel() {
    nonce &+= 1
    isActive = false
    openProgress = 0
    animationComplete = false
    dpadSurfaced = false
  }
}
