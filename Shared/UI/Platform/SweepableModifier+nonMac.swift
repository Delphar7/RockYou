import SwiftUI

  extension View {
    /// Add hold-to-confirm sweep behavior to any view.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name shown in sweep overlay
    ///   - color: Color theme for sweep (background ring, icon tint)
    ///   - delay: How long to hold before action fires (default 1.0s)
    ///   - tooltip: Message shown if released too early (when no onQuickTap handler)
    ///   - gestureStyle: Gesture priority mode (default high priority)
    ///   - onQuickTap: Optional handler for quick tap (released before sweep completes)
    ///   - onSweepComplete: Action to perform when sweep completes
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
      showTooltipOnEarlyRelease: Bool = false,
      gestureStyle: SweepGestureStyle = .highPriority,
      onQuickTap: (() -> Void)? = nil,
      onSweepComplete: @escaping () -> Void
    ) -> some View {
      let overlayDelayNs = UInt64(max(0, overlayDelay) * 1_000_000_000)
      let completionHoldNs = UInt64(max(0, completionHold) * 1_000_000_000)
      return modifier(
        SweepableModifier(
          iconProvider: { .systemName(icon) },
          color: color,
          delay: delay,
          overlayDelay: overlayDelayNs,
          completionHold: completionHoldNs,
          tooltip: tooltip,
          debugName: debugLabel,
          onPressBegan: onPressBegan,
          quickTapPolicy: quickTapPolicy,
          showTooltipOnEarlyRelease: showTooltipOnEarlyRelease,
          gestureStyle: gestureStyle,
          onQuickTap: onQuickTap,
          onSweepComplete: onSweepComplete
        ))
    }

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
      showTooltipOnEarlyRelease: Bool = false,
      gestureStyle: SweepGestureStyle = .highPriority,
      onQuickTap: (() -> Void)? = nil,
      onSweepComplete: @escaping () -> Void
    ) -> some View {
      let overlayDelayNs = UInt64(max(0, overlayDelay) * 1_000_000_000)
      let completionHoldNs = UInt64(max(0, completionHold) * 1_000_000_000)
      return modifier(
        SweepableModifier(
          iconProvider: { .view(AnyView(icon())) },
          color: color,
          delay: delay,
          overlayDelay: overlayDelayNs,
          completionHold: completionHoldNs,
          tooltip: tooltip,
          debugName: debugLabel,
          onPressBegan: onPressBegan,
          quickTapPolicy: quickTapPolicy,
          showTooltipOnEarlyRelease: showTooltipOnEarlyRelease,
          gestureStyle: gestureStyle,
          onQuickTap: onQuickTap,
          onSweepComplete: onSweepComplete
        ))
    }
  }
