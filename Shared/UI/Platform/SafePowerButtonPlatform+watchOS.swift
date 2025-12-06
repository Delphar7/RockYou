import SwiftUI

  enum SafePowerButtonPlatform {
    @MainActor
    static func pairState(selectedDeviceId: String?) -> SafePowerButtonPairState {
      // Watch doesn't have pairing info; treat selected device as a single device.
      let mode = selectedDeviceId.map { DeviceStateManager.shared.state(for: $0).powerMode } ?? .unknown
      return SafePowerButtonPairState(
        isPaired: false,
        isMixed: false,
        tvId: selectedDeviceId,
        streamerId: nil,
        tvMode: mode,
        streamerMode: nil
      )
    }

    static func mixedQuickTap(onPower: @escaping () -> Void) -> () -> Void {
      // Watch: can't directly power both; defer to existing routing.
      onPower
    }

    static func mixedQuickTap(pairState: SafePowerButtonPairState, onPower: @escaping () -> Void) -> () -> Void {
      _ = pairState
      return mixedQuickTap(onPower: onPower)
    }

    static func mixedSweepComplete(onPower: @escaping () -> Void) -> () -> Void {
      onPower
    }

    static func mixedSweepComplete(pairState: SafePowerButtonPairState, onPower: @escaping () -> Void) -> () -> Void {
      _ = pairState
      return mixedSweepComplete(onPower: onPower)
    }

    static func requiresSweepView<ButtonContent: View, PowerLabel: View>(
      buttonContent: ButtonContent,
      powerLabel: PowerLabel,
      backgroundColor: Color,
      seed: UInt64,
      safetyDelay: TimeInterval,
      onPower: @escaping () -> Void
    ) -> AnyView {
      _ = powerLabel
      _ = backgroundColor
      _ = seed
      return AnyView(
        buttonContent
          .sweepable(
            icon: "power",
            color: .red,
            delay: safetyDelay,
            tooltip: "Hold to power off",
            onSweepComplete: onPower
          )
      )
    }

    static func normalOffView<ButtonContent: View, PowerLabel: View>(
      buttonContent: ButtonContent,
      powerLabel: PowerLabel,
      backgroundColor: Color,
      seed: UInt64,
      onPower: @escaping () -> Void
    ) -> AnyView {
      _ = powerLabel
      _ = backgroundColor
      _ = seed
      return AnyView(
        buttonContent
          .onTapGesture {
            HapticService.play(.click)
            onPower()
          }
      )
    }
  }
