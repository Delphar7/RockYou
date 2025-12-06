import SwiftUI

/// Platform-specific policy and gesture attachment for `SweepableModifier` (watchOS).
@MainActor
enum SweepableModifierPlatform {
  static var baseCancelDistance: CGFloat {
    // Keep small so sweep doesn't interfere with ScrollView.
    4
  }

  static var pressBeganPathLabel: String { "watchLongPress" }

  static func prepareForPressBegan() {
    // watchOS: don't auto-dismiss here (SwiftUI can re-enter `pressing(true)` after showing tooltip).
  }

  static func sourceViewDidDisappear() {
    // If the source view disappears (e.g., a sheet is dismissed), don't let tooltips linger.
    TooltipManager.shared.dismiss(immediately: true)
  }

  static var tooltipEmissionPolicy: SweepPressStateMachine.Config.TooltipEmissionPolicy { .overlayOnly }

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
    _ = onMoved

    return AnyView(
      base
        // Hold-to-confirm without fighting ScrollView pan: movement cancels before completion.
        .onLongPressGesture(
          minimumDuration: delay,
          maximumDistance: cancelDistanceInitial,
          pressing: { pressing in
            Log.debug(
              "Sweep",
              "\(debugLabel) pressing=\(pressing) token=\(pressToken) overlayShowing=\(overlayIsShowing)"
            )
            if pressing {
              onBegan()
            } else {
              // Some SwiftUI stacks call `pressing(false)` before the successful `perform`
              // callback. Defer cleanup so `perform` can fire and set completion state first.
              DispatchQueue.main.async {
                onEnded(false)
              }
            }
          },
          perform: {
            Log.debug(
              "Sweep",
              "\(debugLabel) perform token=\(pressToken) overlayShowing=\(overlayIsShowing)"
            )
            onCompleteRequested()
          }
        )
        // On watchOS, scrolling can cancel the long-press recognizer and trigger
        // `pressing(false)` mid-drag. Tooltips should only appear on an actual tap.
        .simultaneousGesture(
          TapGesture()
            .onEnded {
              guard !hasQuickTapHandler else { return }
              guard !tooltip.isEmpty else { return }
              guard !sweepSuppressed else { return }
              guard !machineDidComplete else { return }
              guard !overlayIsShowing else { return }
              TooltipManager.shared.show(tooltip, buttonFrame: buttonFrame)
            }
        )
    )
  }
}
