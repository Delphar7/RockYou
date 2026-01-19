//
//  LockableDPadView.swift
//  RockYou
//
//  Explicit state-machine rewrite of the DPad lock overlay + breaker unlock.
//  Uses the existing BreakerSwitchView, BreakerSwitchSnapshotManager, and BreakerLeverFallAnimator.
//

import SwiftUI

#if os(macOS) && DEBUG
  @MainActor
  enum DebugDPadCapture {
    static var lastRenderedSize: CGFloat?
  }
#endif

/// DPad lock overlay + breaker unlock (state-machine implementation).
struct LockableDPadView: View {
  let onDirection: (RemoteAction) -> Void
  let onOK: () -> Void
  var size: CGFloat? = nil

  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var interactionTracker = UserInteractionTracker.shared
  @ObservedObject private var snapshotManager = BreakerSwitchSnapshotManager.shared
  @State private var settings = AppSettings.shared

  @State private var isLocked = false

  // Single "source of truth" for lever position (0=locked, 1=unlocked).
  @State private var progress: CGFloat = 0
  @State private var domeIsActive: Bool = false
  @State private var domeOpenProgress: CGFloat = 0
  @State private var domeNonce: UInt64 = 0

  // Explicit interaction state (who owns progress).
  private enum Phase {
    case idle
    case dragging(DragSession)
    case settling

    var isIdle: Bool {
      if case .idle = self { return true }
      return false
    }

    var isDragging: Bool {
      if case .dragging = self { return true }
      return false
    }

    var isSettling: Bool {
      if case .settling = self { return true }
      return false
    }
  }

  private struct DragSession {
    var start: CGPoint
    var baseProgress: CGFloat
    var didLockYawSign: Bool
  }

  @State private var phase: Phase = .idle
  @State private var settleToken: UInt64 = 0
  @State private var idleCheckTimer: Timer?
  @State private var liveReady: Bool = false
  @State private var yawSign: CGFloat = 1

  // Must be persistent across SwiftUI view re-creations; otherwise an in-flight timer can
  // keep ticking on an old instance while the new instance can't cancel it.
  @State private var leverFallAnimator = BreakerLeverFallAnimator()

  /// Lock timeout from settings (nil = Off)
  private var lockTimeout: TimeInterval? {
    settings.dpadLockTimeout
  }

  /// Snapshot should only be shown when truly idle.
  private let snapshotIdleProgressThreshold: CGFloat = 0.0001

  /// Snapshot render size relative to DPad size (1.2x for extra headroom)
  private let breakerSnapshotSizeMultiplier: CGFloat = 1.2

  /// Snapshot configuration (iOS defaults)
  private let snapshotInitialDelaySeconds: TimeInterval = 2.0
  private let snapshotShouldForceOnLockIfMissing: Bool = false

  var body: some View {
    Group {
      if let explicitSize = size {
        dpadBody(dpadSize: explicitSize)
          #if os(macOS) && DEBUG
            .onAppear { DebugDPadCapture.lastRenderedSize = explicitSize }
            .onChange(of: explicitSize) { _, newValue in
              DebugDPadCapture.lastRenderedSize = newValue
            }
          #endif
      } else {
        GeometryReader { geo in
          let dpadSize = min(geo.size.width, geo.size.height)
          dpadBody(dpadSize: dpadSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS) && DEBUG
              .onAppear { DebugDPadCapture.lastRenderedSize = dpadSize }
              .onChange(of: dpadSize) { _, newValue in DebugDPadCapture.lastRenderedSize = newValue
              }
            #endif
        }
      }
    }
    .onAppear {
      idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        checkIdleTimeout()
      }
      checkIdleTimeout()
    }
    .onDisappear {
      idleCheckTimer?.invalidate()
      idleCheckTimer = nil
      leverFallAnimator.stop()
    }
    .onChange(of: scenePhase) { _, newValue in
      guard newValue == .active else { return }
      handleAppBecameActive()
    }
    .modifier(
      DebugCrashAlertModifier(title: "Invariant Violation") {
        guard DebugBuild.isEnabled else { return nil }

        let snapshotDelay = snapshotInitialDelaySeconds
        guard let idleLockDelay = lockTimeout else { return nil }
        let slack: TimeInterval = 1.0
        guard (snapshotDelay + slack) < idleLockDelay else {
          return
            "Breaker snapshot delay must be comfortably less than idle lock timeout.\n\n"
            + "snapshotDelay=\(String(format: "%.2fs", snapshotDelay))\n"
            + "idleLockTimeout=\(String(format: "%.2fs", idleLockDelay))\n"
            + "required: snapshotDelay + \(String(format: "%.2fs", slack)) < idleLockTimeout"
        }
        return nil
      })
  }

  private func dpadBody(dpadSize: CGFloat) -> some View {
    DPadView(
      onDirection: isLocked ? { _ in } : onDirection,
      onOK: isLocked ? {} : onOK,
      size: dpadSize
    )
    .allowsHitTesting(!isLocked)
    .opacity(domeIsActive ? 0 : 1)
    .onAppear {
      requestSnapshot(dpadSize: dpadSize)
    }
    .overlay {
      if isLocked {
        lockOverlay(dpadSize: dpadSize)
      } else if domeIsActive {
        domeOverlay(dpadSize: dpadSize)
      }
    }
  }

  private func domeOverlay(dpadSize: CGFloat) -> some View {
    // Dome sequence (RealityKit):
    // - Shader blends regular/refracted DPad textures based on iris mask.
    // - No black ellipse needed - shader handles masking.
    let domeSize = dpadSize * CGFloat(DomeSceneConfig.renderCanvasScale)
    let p = min(1, max(0, domeOpenProgress))

    return DomeDoorsView(openProgress: p)
      .frame(width: domeSize, height: domeSize)
      .frame(width: dpadSize, height: dpadSize, alignment: .center)
      .allowsHitTesting(false)
  }

  @MainActor
  private func showAndOpenDome() {
    domeNonce &+= 1
    let nonce = domeNonce
    let openDurationSeconds: TimeInterval = 8.0
    let teardownDelaySeconds: TimeInterval = 0.25
    let frameIntervalSeconds: TimeInterval = 1.0 / 60.0

    withTransaction(Transaction(animation: nil)) {
      domeIsActive = true
      domeOpenProgress = 0
    }

    Task { @MainActor in
      Log.debug(
        "DomeDoors",
        "Start dome open: duration=\(String(format: "%.2f", openDurationSeconds))s nonce=\(nonce)"
      )
      // Allow the dome view to mount before animating progress.
      await Task.yield()
      guard domeNonce == nonce else {
        Log.debug("DomeDoors", "Canceled before start: nonce changed")
        return
      }

      let start = Date()
      while domeNonce == nonce {
        let elapsed = Date().timeIntervalSince(start)
        let progress = min(1.0, max(0, elapsed / openDurationSeconds))
        domeOpenProgress = progress
        if progress >= 1.0 { break }
        try? await Task.sleep(nanoseconds: UInt64(frameIntervalSeconds * 1_000_000_000))
      }

      let elapsedTotal = Date().timeIntervalSince(start)
      if domeNonce != nonce {
        Log.debug(
          "DomeDoors",
          "Canceled mid-open: elapsed=\(String(format: "%.2f", elapsedTotal))s nonce=\(nonce)"
        )
        return
      }

      Log.debug(
        "DomeDoors",
        "Open complete: elapsed=\(String(format: "%.2f", elapsedTotal))s nonce=\(nonce)"
      )

      // Remove shortly after open completes.
      try? await Task.sleep(nanoseconds: UInt64(teardownDelaySeconds * 1_000_000_000))
      guard domeNonce == nonce else { return }
      Log.debug("DomeDoors", "Teardown dome: nonce=\(nonce)")
      domeIsActive = false
    }
  }

  private func requestSnapshot(dpadSize: CGFloat) {
    let snapSize = CGSize(
      width: dpadSize * breakerSnapshotSizeMultiplier,
      height: dpadSize * breakerSnapshotSizeMultiplier
    )
    snapshotManager.requestSnapshot(size: snapSize)
  }

  private func lockOverlay(dpadSize: CGFloat) -> some View {
    let breakerFrameMultiplier: CGFloat = 1.33
    let breakerSize = dpadSize * breakerFrameMultiplier
    let breakerVerticalShift = -dpadSize * 0.0
    let ellipse = lockEllipseMetrics(dpadSize: dpadSize)

    return GeometryReader { geo in
      let hasSnapshot = (snapshotManager.snapshot != nil)

      // Render policy:
      // - Idle: snapshot-only (keep RealityView out of hierarchy for GPU)
      // - Dragging/Settling: live view inserted; snapshot overlays live until `liveReady`
      let isIdle = phase.isIdle && (progress <= snapshotIdleProgressThreshold)
      let shouldWarmLive = !isIdle
      let showSnapshot = hasSnapshot && (isIdle || (shouldWarmLive && !liveReady))

      let cameraYawOffsetDegrees =
        Float(yawSign)
        * BreakerSceneConfig.unlockCameraYawSlopeFlipSign
        * BreakerSceneConfig.unlockCameraYawMaxDegrees
        * Float(progress)

      ZStack {
        Ellipse()
          .fill(Color.black.opacity(0.95))
          .frame(width: ellipse.width, height: ellipse.height)
          .contentShape(Rectangle())
          .offset(y: ellipse.verticalShift)
          .gesture(unlockGesture(dpadSize: dpadSize))

        if let snapshot = snapshotManager.snapshot {
          PlatformImage.swiftUIImage(from: snapshot)
            .resizable()
            .frame(width: breakerSize, height: breakerSize)
            .offset(y: breakerVerticalShift)
            .opacity(showSnapshot ? 1 : 0)
            .allowsHitTesting(false)
        }

        if shouldWarmLive {
          BreakerSwitchView(
            progress: progress,
            cameraYawDegreesOffset: cameraYawOffsetDegrees,
            onReady: {
              withTransaction(Transaction(animation: nil)) {
                liveReady = true
              }
            }
          )
          .frame(width: breakerSize, height: breakerSize)
          .offset(y: breakerVerticalShift)
          .opacity(showSnapshot ? 0 : 1)
          .allowsHitTesting(false)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
      .transaction { txn in txn.animation = nil }
      .onAppear {
        Log.debug("BreakerSwitch", "⏱️ Lock overlay appeared (SM)")

        let snapSize = CGSize(
          width: dpadSize * breakerSnapshotSizeMultiplier,
          height: dpadSize * breakerSnapshotSizeMultiplier
        )
        if progress == 0, snapshotManager.snapshot == nil,
          snapshotShouldForceOnLockIfMissing
        {
          Log.warn("BreakerSwitch", "Snapshot missing at lock time; forcing on-demand render")
          snapshotManager.forceSnapshot(size: snapSize, reason: "lockOverlay-missing")
        } else {
          snapshotManager.requestSnapshot(size: snapSize)
        }
      }
    }
    .frame(width: dpadSize, height: dpadSize, alignment: .center)
  }

  // MARK: - Gesture

  private func unlockGesture(dpadSize: CGFloat) -> some Gesture {
    let unlockSwipeDistance = dpadSize * 1.0
    let inertiaGain: CGFloat = 0.5
    let maxInertialBoost: CGFloat = 1.25
    let inertiaAnimationDurationSeconds: Double = 0.14
    let minInertialOvershootPoints: CGFloat = 8
    let minInertialOvershootProgress: CGFloat = 0.005

    func contribution(deltaY: CGFloat) -> CGFloat {
      max(0, -deltaY) / unlockSwipeDistance
    }

    func progressFor(deltaY: CGFloat, base: CGFloat) -> CGFloat {
      min(1.0, base + contribution(deltaY: deltaY))
    }

    func beginDragIfNeeded(startLocation: CGPoint) {
      guard !phase.isDragging else { return }

      // Drag owns immediately: capture base progress, then stop animations.
      let wasIdle = phase.isIdle
      let base = progress
      phase = .dragging(
        DragSession(start: startLocation, baseProgress: base, didLockYawSign: false))

      // Invalidate any in-flight settling ticks first, then stop the timer.
      // This guarantees drag wins even if one last timer tick fires before invalidate takes effect.
      settleToken &+= 1
      leverFallAnimator.stop()

      // Only "warm up" the live view (and keep snapshot visible) when we were truly idle.
      // If the live view is already in the hierarchy (e.g. interrupting a settle near 0),
      // resetting `liveReady` would incorrectly force the snapshot to cover the live lever
      // and make it appear unresponsive during drag.
      if wasIdle && base <= snapshotIdleProgressThreshold {
        liveReady = false
      }

      interactionTracker.noteInteraction()
    }

    func endDrag(
      start: CGPoint,
      base: CGFloat,
      endLocation: CGPoint,
      predictedEndLocation: CGPoint
    ) {
      // Compute end and predicted progress.
      let endDeltaY = endLocation.y - start.y
      let predDeltaY = predictedEndLocation.y - start.y

      let endProgress = progress
      var targetProgress = endProgress

      // Inertial boost: compute predicted - end, deadzoned.
      if endDeltaY < 0 {
        let endContribution = contribution(deltaY: endDeltaY)
        let predContribution = contribution(deltaY: predDeltaY)
        let extra = max(0, predContribution - endContribution)
        let overshootPoints = max(0, abs(predDeltaY) - abs(endDeltaY))
        if overshootPoints >= minInertialOvershootPoints, extra >= minInertialOvershootProgress {
          let inertialBoost = min(maxInertialBoost, extra * inertiaGain)
          targetProgress = min(1.0, base + endContribution + inertialBoost)
        }
      }

      // Resolve: unlock or settle back.
      if targetProgress >= 1.0 {
        HapticService.notifySuccess()
        interactionTracker.noteInteraction()
        // No animation - dome transition handles the visual continuity
        withTransaction(Transaction(animation: nil)) {
          isLocked = false
          progress = 0
        }
        phase = .idle
        showAndOpenDome()
        return
      }

      // Enter settling; any new drag will interrupt by bumping `settleToken` and stopping the animator.
      settleToken &+= 1
      let token = settleToken
      phase = .settling

      func startReturn() {
        guard settleToken == token, phase.isSettling else { return }
        HapticService.play(.click)
        leverFallAnimator.start(
          from: progress,
          onUpdate: { p in
            guard settleToken == token, phase.isSettling else { return }
            progress = p
          },
          onBounceImpact: { bounceNumber in
            if bounceNumber == 1 {
              HapticService.play(.rigid)
            } else {
              HapticService.play(.start)
            }
          },
          onComplete: {
            guard settleToken == token, phase.isSettling else { return }
            phase = .idle
          }
        )
      }

      if targetProgress > endProgress {
        leverFallAnimator.startInertialContinuation(
          from: endProgress,
          to: targetProgress,
          durationSeconds: inertiaAnimationDurationSeconds,
          onUpdate: { p in
            guard settleToken == token, phase.isSettling else { return }
            progress = p
          },
          onComplete: {
            startReturn()
          }
        )
      } else {
        startReturn()
      }
    }

    return DragGesture(minimumDistance: 0)
      .onChanged { value in
        beginDragIfNeeded(startLocation: value.startLocation)
        guard case .dragging(var session) = phase else { return }

        let deltaY = value.location.y - session.start.y
        let deltaX = value.location.x - session.start.x

        // Lock yaw sign on first meaningful upward segment.
        if !session.didLockYawSign, deltaY < 0 {
          let dist = hypot(deltaX, deltaY)
          if dist >= 6 {
            yawSign = (deltaX >= 0) ? 1 : -1
            session.didLockYawSign = true
            phase = .dragging(session)
          }
        }

        // Only accept upward drags; otherwise hold current progress (no snapping).
        guard deltaY < 0 else { return }

        progress = progressFor(deltaY: deltaY, base: session.baseProgress)
      }
      .onEnded { value in
        guard case .dragging(let session) = phase else { return }

        // End drag: settle/unlock. Keep live in hierarchy during settle.
        endDrag(
          start: session.start,
          base: session.baseProgress,
          endLocation: value.location,
          predictedEndLocation: value.predictedEndLocation
        )
      }
  }

  // MARK: - Idle locking

  private func checkIdleTimeout() {
    guard let timeout = lockTimeout else { return }
    guard !domeIsActive else { return }
    let timeSinceInteraction = Date().timeIntervalSince(interactionTracker.lastInteractionAt)
    if timeSinceInteraction >= timeout && !isLocked {
      withAnimation(.easeInOut(duration: 0.5)) {
        isLocked = true
      }
      // Reset state for new lock session.
      resetLockSessionState()
      HapticService.play(.warning)
    }
  }

  private func handleAppBecameActive() {
    interactionTracker.noteInteraction()
    guard isLocked else { return }

    withAnimation(.easeInOut(duration: 0.3)) {
      isLocked = false
    }
    resetLockSessionState()
  }

  private func resetLockSessionState() {
    settleToken &+= 1
    leverFallAnimator.stop()
    progress = 0
    phase = .idle
    liveReady = false
    domeIsActive = false
    domeOpenProgress = 0
    domeNonce &+= 1
  }
}

private func lockEllipseMetrics(dpadSize: CGFloat) -> (
  width: CGFloat, height: CGFloat, verticalShift: CGFloat
) {
  let width = dpadSize * 1.05
  let height = dpadSize * 1.1
  let verticalShift = (height - width) / 4
  return (width, height, verticalShift)
}
