//
//  LockableDPadView.swift
//  RockYou (iOS)
//
//  Wraps DPadView with idle-timeout locking and breaker switch unlock.
//

import SwiftUI

struct LockableDPadView: View {
  let onDirection: (RemoteAction) -> Void
  let onOK: () -> Void
  var size: CGFloat? = nil

  @ObservedObject private var interactionTracker = UserInteractionTracker.shared
  @ObservedObject private var snapshotManager = BreakerSwitchSnapshotManager.shared
  @State private var isLocked = false
  @State private var unlockProgress: CGFloat = 0.0
  @State private var progressAtDragStart: CGFloat = 0.0  // For gesture interruption
  @State private var unlockDragStart: CGPoint? = nil
  @State private var idleCheckTimer: Timer?
  /// Only use the snapshot during this lock session if it was already available at lock time.
  /// This prevents mid-lock live↔snapshot swapping (which looks like a blink/fade).
  @State private var snapshotEligibleForCurrentLock: Bool = false

  // Lock after idle time (5 seconds in DEBUG, 30 seconds in release)
  private var lockTimeout: TimeInterval {
    DebugBuild.isEnabled ? 5.0 : 30.0
  }

  private let unlockSwipeDistance: CGFloat = 150  // Distance to swipe for unlock
  /// Prevents tiny gesture noise from flipping snapshot ↔ live view (visual "blink").
  private let snapshotToLiveProgressThreshold: CGFloat = 0.02

  var body: some View {
    Group {
      if let explicitSize = size {
        dpadBody(dpadSize: explicitSize)
      } else {
        GeometryReader { geo in
          let dpadSize = min(geo.size.width, geo.size.height)
          dpadBody(dpadSize: dpadSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .onAppear {
      // Start a timer to periodically check for idle timeout
      idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        checkIdleTimeout()
      }
      checkIdleTimeout()
    }
    .onDisappear {
      idleCheckTimer?.invalidate()
      idleCheckTimer = nil
    }
  }

  private func dpadBody(dpadSize: CGFloat) -> some View {
    DPadView(
      onDirection: isLocked ? { _ in } : onDirection,  // Disable when locked
      onOK: isLocked ? {} : onOK,
      size: dpadSize
    )
    .opacity(isLocked ? 0.1 : 1.0)
    .allowsHitTesting(!isLocked)
    // .animation(.easeInOut(duration: 0.3), value: isLocked)  // Disabled for debugging
    .onAppear {
      // Prefetch snapshot even when unlocked so the first lock can use it immediately.
      let snapSize = CGSize(width: dpadSize * 1.2, height: dpadSize * 1.2)
      snapshotManager.requestSnapshot(size: snapSize)
    }
    .overlay {
      if isLocked {
        lockOverlay(dpadSize: dpadSize)
      }
    }
  }

  /// Lock visuals/gestures overlaid on a fixed DPad-sized coordinate space.
  /// This MUST NOT participate in layout (so it doesn't stretch and push other controls around).
  private func lockOverlay(dpadSize: CGFloat) -> some View {
    // Layout constants for breaker overlay
    let breakerFrameMultiplier: CGFloat = 2  // Frame size relative to dpad - room for handle swing
    let breakerSize = dpadSize * breakerFrameMultiplier
    let verticalShift = -dpadSize * 0.58  // Shift up to avoid bottom button

    let ellipseWidth = dpadSize * 1.05
    let ellipseHeight = dpadSize * 1.25
    let ellipseOffset = (ellipseHeight - dpadSize) / 2

    return GeometryReader { geo in
      ZStack {
        // Dark background ellipse to match dpad with shadow
        Ellipse()
          .fill(Color.black.opacity(0.85))
          //.overlay(Ellipse().stroke(Color.red, lineWidth: 2))  // DEBUG: visualize bounds
          .frame(width: ellipseWidth, height: ellipseHeight)
          .offset(y: verticalShift + ellipseOffset)

        // Breaker switch (larger frame for arc room)
        // iOS: Use static snapshot when idle to avoid continuous GPU rendering
        // macOS: Also supports snapshot to avoid continuous GPU rendering.

        if snapshotEligibleForCurrentLock,
          unlockProgress < snapshotToLiveProgressThreshold,
          let snapshot = snapshotManager.snapshot
        {
          PlatformImage.swiftUIImage(from: snapshot)
            .resizable()
            .frame(width: breakerSize, height: breakerSize)
            .offset(y: verticalShift)
            .allowsHitTesting(false)  // Let touches pass through to gesture handler
        } else {
          BreakerSwitchView(progress: unlockProgress)
            .frame(width: breakerSize, height: breakerSize)
            .offset(y: verticalShift)
        }

        // Tap behavior: macOS = unlock, iOS = show tooltip
        Color.clear
          .contentShape(Ellipse())
          .onTapGesture {
            handleLockOverlayTap(
              globalFrame: geo.frame(in: .global),
              dpadSize: dpadSize,
              unlock: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                  isLocked = false
                  unlockProgress = 0
                }
              }
            )
          }
      }
      // IMPORTANT: Keep the overlay's *layout* coordinate space pinned to the DPad square.
      // Children may be larger and intentionally overflow, but they must remain center-aligned
      // relative to the DPad.
      .frame(width: geo.size.width, alignment: .center)
      .gesture(unlockGesture(dpadSize: dpadSize))
      .onAppear {
        snapshotEligibleForCurrentLock = (snapshotManager.snapshot != nil)
        let snapSize = CGSize(width: dpadSize * 1.2, height: dpadSize * 1.2)
        if unlockProgress == 0, snapshotManager.snapshot == nil {
          Log.warn("BreakerSwitch", "Snapshot missing at lock time; forcing on-demand render")
          snapshotManager.forceSnapshot(size: snapSize, reason: "lockOverlay-missing")
        } else {
          snapshotManager.requestSnapshot(size: snapSize)
        }
      }
      .onDisappear {
        snapshotEligibleForCurrentLock = false
      }
    }
    // Critical: bind overlay's layout footprint to the DPad square.
    // The ellipse/breaker may render outside this square (by design), but layout stays stable.
    .frame(width: dpadSize, height: dpadSize, alignment: .center)
  }

  private func unlockGesture(dpadSize: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if unlockDragStart == nil {
          unlockDragStart = value.startLocation
          // Capture current progress (allows resuming mid-animation)
          progressAtDragStart = unlockProgress
        }

        guard let start = unlockDragStart else { return }

        // Calculate upward distance (negative Y = up)
        let deltaY = value.location.y - start.y

        // Only accept upward drags
        guard deltaY < 0 else {
          // User dragged down - return toward locked but not below base
          unlockProgress = progressAtDragStart
          return
        }

        // Calculate gesture contribution and add to base
        let gestureContribution = abs(deltaY) / unlockSwipeDistance
        unlockProgress = min(1.0, progressAtDragStart + gestureContribution)
      }
      .onEnded { _ in
        if unlockProgress >= 1.0 {
          // Unlock!
          HapticService.notifySuccess()
          withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isLocked = false
            unlockProgress = 0
          }
        } else {
          // Animate lever back to locked position (slow, weighty feel)
          HapticService.play(.click)
          withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            unlockProgress = 0
          }
        }

        unlockDragStart = nil
        progressAtDragStart = 0
      }
  }

  private func checkIdleTimeout() {
    let timeSinceInteraction = Date().timeIntervalSince(interactionTracker.lastInteractionAt)

    if timeSinceInteraction >= lockTimeout && !isLocked {
      // Lock the dpad
      withAnimation(.easeInOut(duration: 0.5)) {
        isLocked = true
      }
      HapticService.play(.warning)
    }
  }

}
