import SwiftUI

/// Platform-specific policy and gesture attachment for `SweepableModifier` (iOS).
@MainActor
enum SweepableModifierPlatform {
  static var baseCancelDistance: CGFloat { 12 }
  static var pressBeganPathLabel: String { "routerOrLongPress" }

  static func prepareForPressBegan() {
    // iOS/iPadOS: clear any tooltip before beginning a new press/hold.
    TooltipManager.shared.dismiss()
  }

  static func sourceViewDidDisappear() {
    // no-op
  }

  static var tooltipEmissionPolicy: SweepPressStateMachine.Config.TooltipEmissionPolicy { .always }

  static func attachGestureDriver<Base: View>(
    base: Base,
    buttonFrame: CGRect,
    sweepSuppressed: Bool,
    debugLabel: String,
    pressToken: UInt64,
    delay: TimeInterval,
    cancelDistanceInitial: CGFloat,
    tooltip: String,
    hasQuickTapHandler: Bool,
    machineDidComplete: Bool,
    overlayIsShowing: Bool,
    onBegan: @escaping () -> Void,
    onMoved: @escaping (CGFloat) -> Void,
    onEnded: @escaping (Bool) -> Void,
    onCompleteRequested: @escaping () -> Void
  ) -> AnyView {
    _ = pressToken
    _ = delay
    _ = cancelDistanceInitial
    _ = tooltip
    _ = hasQuickTapHandler
    _ = machineDidComplete
    _ = overlayIsShowing
    _ = onCompleteRequested

    return AnyView(
      base.background(
        SweepableTouchRouterInstaller(
          frame: buttonFrame,
          suppressed: sweepSuppressed,
          debugLabel: debugLabel,
          onBegan: onBegan,
          onMoved: onMoved,
          onEnded: onEnded
        )
      )
    )
  }
}
