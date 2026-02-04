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

  /// Name of the currently running dome animation (e.g. "Spiral Iris").
  /// Set by DomeDoorsView on appear; persists until the next animation replaces it.
  @Published private(set) var animationName: String = ""

  /// Old dome frame size for viewport scale compensation.
  @Published private(set) var referenceDomeSize: CGFloat = 0

  /// DPad center Y in global coordinate space (set by LockableDPadView).
  /// Used by FullScreenDomeView to center the dome on the DPad.
  var dpadGlobalCenterY: CGFloat = 0

  private var nonce: UInt64 = 0

  private init() {}

  /// Activates the dome animation and drives `openProgress` from 0→1
  /// over `DomeSceneConfig.duration` wall-clock seconds. At progress=1
  /// the DPad surfaces (soft cap). The animation continues in the background
  /// for another `duration` seconds (hard cap at 2×), unless the shader
  /// reports completion earlier via `reportComplete()`.
  func start(referenceDomeSize: CGFloat) {
    nonce &+= 1
    let myNonce = nonce
    let wallClockDuration = TimeInterval(DomeSceneConfig.duration)
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
        "Start dome open: duration=\(String(format: "%.2f", wallClockDuration))s nonce=\(myNonce)"
      )
      // Allow the dome view to mount before animating progress.
      await Task.yield()
      guard nonce == myNonce else {
        Log.debug("DomeDoors", "Canceled before start: nonce changed")
        return
      }

      // Phase 1: Drive openProgress from 0 to 1 over wall-clock duration.
      let start = Date()
      while nonce == myNonce {
        let elapsed = Date().timeIntervalSince(start)
        let progress = min(1.0, max(0, elapsed / wallClockDuration))
        openProgress = progress
        if progress >= 1.0 { break }
        try? await Task.sleep(nanoseconds: UInt64(frameIntervalSeconds * 1_000_000_000))
      }

      if nonce != myNonce {
        Log.debug("DomeDoors", "Canceled mid-open: nonce changed")
        return
      }

      // Surface the DPad — user gets controls back immediately.
      dpadSurfaced = true
      Log.debug(
        "DomeDoors",
        "DPad surfaced at \(String(format: "%.2f", Date().timeIntervalSince(start)))s nonce=\(myNonce)"
      )

      // Phase 2: Keep driving openProgress beyond 1.0 so shader time
      // continues advancing (fragments keep falling/drifting in background).
      // Hard cap at 2× wall-clock duration, or until shader reports completion.
      while nonce == myNonce && !animationComplete {
        let totalElapsed = Date().timeIntervalSince(start)
        let backgroundElapsed = totalElapsed - wallClockDuration
        if backgroundElapsed >= wallClockDuration { break }
        openProgress = totalElapsed / wallClockDuration
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
    dpadSurfaced = true  // User gets their DPad back immediately
  }

  /// Cancels any running dome animation and resets all state.
  func cancel() {
    nonce &+= 1
    isActive = false
    openProgress = 0
    animationComplete = false
    dpadSurfaced = false
  }

  /// Sets the animation name (called by DomeDoorsView on selection).
  func setAnimationName(_ name: String) {
    animationName = name
  }
}
