//
//  SweepPressStateMachineTests.swift
//  RockYouTests
//

import CoreGraphics
import Foundation
import Testing
@testable import RockYou

@MainActor
struct SweepPressStateMachineTests {

  private func makeConfig(
    delay: TimeInterval = 1.0,
    overlayDelay: TimeInterval = 0.25,
    cancelInitial: CGFloat = 10,
    cancelLocked: CGFloat = 20,
    hasQuickTap: Bool,
    quickTapPolicy: SweepQuickTapPolicy = .anyReleaseBeforeComplete,
    tooltipEmissionPolicy: SweepPressStateMachine.Config.TooltipEmissionPolicy = .always,
    tooltip: String = "Hold"
  ) -> SweepPressStateMachine.Config {
    SweepPressStateMachine.Config(
      delay: delay,
      overlayDelay: overlayDelay,
      cancelDistanceInitial: cancelInitial,
      cancelDistanceLocked: cancelLocked,
      hasQuickTapHandler: hasQuickTap,
      quickTapPolicy: quickTapPolicy,
      tooltipEmissionPolicy: tooltipEmissionPolicy,
      tooltipText: tooltip
    )
  }

  @Test func quickTap_firesQuickTap_whenHandlerExists() async throws {
    var m = SweepPressStateMachine(config: makeConfig(hasQuickTap: true))
    let t0: TimeInterval = 100

    #expect(m.pressBegan(now: t0) == [SweepPressStateMachine.Action.pressedChanged(true)])
    #expect(m.tick(now: t0 + 0.05).isEmpty)

    let end = m.pressEnded(cancelled: false, now: t0 + 0.06)
    #expect(end.contains(SweepPressStateMachine.Action.pressedChanged(false)))
    #expect(end.contains(SweepPressStateMachine.Action.endCleanup))
    #expect(end.contains(SweepPressStateMachine.Action.quickTap))
    #expect(!end.contains(SweepPressStateMachine.Action.overlayShown))
    #expect(!end.contains { if case .showTooltip = $0 { return true }; return false })
  }

  @Test func holdToComplete_showsOverlay_thenCompletes() async throws {
    var m = SweepPressStateMachine(config: makeConfig(hasQuickTap: false))
    let t0: TimeInterval = 0

    _ = m.pressBegan(now: t0)
    #expect(m.tick(now: t0 + 0.10).isEmpty)

    let overlay = m.tick(now: t0 + 0.25)
    #expect(overlay == [SweepPressStateMachine.Action.overlayShown])

    let done = m.tick(now: t0 + 1.00)
    #expect(done.contains(SweepPressStateMachine.Action.completed))
    #expect(done.contains(SweepPressStateMachine.Action.pressedChanged(false)))
    #expect(!done.contains(SweepPressStateMachine.Action.endCleanup))
  }

  @Test func dragCancel_beforeOverlay_cancelsWithInitialThreshold() async throws {
    var m = SweepPressStateMachine(
      config: makeConfig(cancelInitial: 10, cancelLocked: 20, hasQuickTap: false)
    )
    let t0: TimeInterval = 10

    _ = m.pressBegan(now: t0)
    let actions = m.moved(distance: 11, now: t0 + 0.01)

    #expect(actions.contains(SweepPressStateMachine.Action.pressedChanged(false)))
    #expect(actions.contains(SweepPressStateMachine.Action.endCleanup))
    #expect(
      actions.contains {
        if case .cancelled(reason: .draggedBeyondThreshold(distance: 11, threshold: 10, locked: false)) = $0 {
          return true
        }
        return false
      }
    )
    #expect(m.isPressed == false)
  }

  @Test func suppressionWhilePressed_cancels() async throws {
    var m = SweepPressStateMachine(config: makeConfig(hasQuickTap: false))
    let t0: TimeInterval = 50

    _ = m.pressBegan(now: t0)
    let actions = m.setSuppressed(true, now: t0 + 0.01)

    #expect(actions.contains(SweepPressStateMachine.Action.pressedChanged(false)))
    #expect(actions.contains(SweepPressStateMachine.Action.endCleanup))
    #expect(
      actions.contains {
        if case .cancelled(reason: .suppressed) = $0 { return true }
        return false
      }
    )
  }

  @Test func quickTapPolicy_onlyIfOverlayNotShown_suppressesQuickTap_andMayShowTooltip() async throws {
    var m = SweepPressStateMachine(
      config: makeConfig(
        delay: 1.0,
        overlayDelay: 0.25,
        hasQuickTap: true,
        quickTapPolicy: .onlyIfOverlayNotShown,
        tooltip: "Hold"
      )
    )
    let t0: TimeInterval = 0

    _ = m.pressBegan(now: t0)
    #expect(m.tick(now: t0 + 0.25) == [SweepPressStateMachine.Action.overlayShown])

    let end = m.pressEnded(cancelled: false, now: t0 + 0.30)
    #expect(!end.contains(SweepPressStateMachine.Action.quickTap))
    #expect(end.contains(SweepPressStateMachine.Action.endCleanup))
    #expect(
      end.contains {
        if case .showTooltip(reason: .quickAbandonOverlay) = $0 { return true }
        return false
      }
    )
  }

  @Test func noTooltip_ifOverlayWasVisibleForLongEnough() async throws {
    var m = SweepPressStateMachine(
      config: makeConfig(delay: 2.0, overlayDelay: 0.1, hasQuickTap: false, tooltip: "Hold")
    )
    let t0: TimeInterval = 0

    _ = m.pressBegan(now: t0)
    #expect(m.tick(now: t0 + 0.1) == [SweepPressStateMachine.Action.overlayShown])

    // Threshold is max(delay/2, 0.5) = 1.0. Release after 1.5s since overlay => no tooltip.
    let end = m.pressEnded(cancelled: false, now: t0 + 1.6)
    #expect(end.contains(SweepPressStateMachine.Action.endCleanup))
    #expect(!end.contains { if case .showTooltip = $0 { return true }; return false })
  }
}
