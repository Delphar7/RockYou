//
//  SweepableModifier+macOS.swift
//  RockYou (Shared)
//
//  macOS-specific no-op implementation of sweepable modifier.
//  On macOS, app icons are tap-to-launch only (no hold-to-confirm).
//  This allows drag scrolling to work smoothly without gesture conflicts.
//

import SwiftUI

  extension View {
    /// macOS: Converts to simple tap gesture. App icons are tap-to-launch only.
    /// This prevents gesture conflicts with drag scrolling while ensuring the action fires.
    func sweepable(
      icon: String,
      color: Color,
      delay: TimeInterval = 1.0,
      overlayDelay: TimeInterval = 0.10,
      completionHold: TimeInterval = 0.5,
      tooltip: String,
      debugLabel: String = "",
      onPressBegan: (() -> Void)? = nil,
      quickTapPolicy: SweepQuickTapPolicy = .anyReleaseBeforeComplete,
      onQuickTap: (() -> Void)? = nil,
      onSweepComplete: @escaping () -> Void
    ) -> some View {
      // On macOS, use simultaneous gesture so drags can pass through to scroll view
      // Use onQuickTap if provided, otherwise use onSweepComplete
      let action = onQuickTap ?? onSweepComplete
      return self.simultaneousGesture(
        TapGesture()
          .onEnded {
            _ = debugLabel
            _ = quickTapPolicy
            onPressBegan?()
            action()
          }
      )
    }

    /// macOS: Converts to simple tap gesture. App icons are tap-to-launch only.
    /// This prevents gesture conflicts with drag scrolling while ensuring the action fires.
    func sweepable<Icon: View>(
      icon: @escaping () -> Icon,
      color: Color,
      delay: TimeInterval = 1.0,
      overlayDelay: TimeInterval = 0.10,
      completionHold: TimeInterval = 0.15,
      tooltip: String,
      debugLabel: String = "",
      onPressBegan: (() -> Void)? = nil,
      quickTapPolicy: SweepQuickTapPolicy = .anyReleaseBeforeComplete,
      onQuickTap: (() -> Void)? = nil,
      onSweepComplete: @escaping () -> Void
    ) -> some View {
      // On macOS, use simultaneous gesture so drags can pass through to scroll view
      // Use onQuickTap if provided, otherwise use onSweepComplete
      let action = onQuickTap ?? onSweepComplete
      return self.simultaneousGesture(
        TapGesture()
          .onEnded {
            _ = debugLabel
            _ = quickTapPolicy
            onPressBegan?()
            action()
          }
      )
    }
  }
