import SwiftUI

/// Platform-specific policy and gesture attachment for `SweepableModifier` (macOS).
@MainActor
enum SweepableModifierPlatform {
  static var baseCancelDistance: CGFloat { 12 }
  static var pressBeganPathLabel: String { "routerOrLongPress" }

  static func prepareForPressBegan() {
    // macOS: clear any tooltip before beginning a new press/hold.
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
    _ = sweepSuppressed
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
