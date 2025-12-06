import SwiftUI

  enum SafePowerButtonPlatform {
    @MainActor
    static func pairState(selectedDeviceId: String?) -> SafePowerButtonPairState {
      let store = PairingStore.shared
      let tvId = store.currentTVId
      let streamerId = tvId.flatMap { store.streamerIdForTV($0) }

      let tvMode = tvId.map { DeviceStateManager.shared.state(for: $0).powerMode } ?? .unknown
      let streamerMode = streamerId.map { DeviceStateManager.shared.state(for: $0).powerMode }

      let isPaired = (tvId != nil && streamerId != nil)
      let isMixed = isPaired && (tvMode.isOn != (streamerMode?.isOn ?? false))

      _ = selectedDeviceId // selection is represented by the pairing store on non-watch platforms
      return SafePowerButtonPairState(
        isPaired: isPaired,
        isMixed: isMixed,
        tvId: tvId,
        streamerId: streamerId,
        tvMode: tvMode,
        streamerMode: streamerMode
      )
    }

    static func mixedQuickTap(pairState: SafePowerButtonPairState, onPower: @escaping () -> Void) -> () -> Void {
      {
        HapticService.play(.click)
        powerOnOffDevicesInPair(pairState: pairState, onPower: onPower)
      }
    }

    static func mixedSweepComplete(pairState: SafePowerButtonPairState, onPower: @escaping () -> Void) -> () -> Void {
      {
        powerOffOnDevicesInPair(pairState: pairState, onPower: onPower)
      }
    }

    static func requiresSweepView<ButtonContent: View, Label: View>(
      buttonContent: ButtonContent,
      powerLabel: Label,
      backgroundColor: Color,
      seed: UInt64,
      safetyDelay: TimeInterval,
      onPower: @escaping () -> Void
    ) -> AnyView {
      let shape = Capsule()
      _ = buttonContent

      return AnyView(
        powerLabel
          .foregroundStyle(Color.clear)
          .tint(.clear)
          .contentShape(shape)
          .overlay {
            SafePowerButton.SweepPressedReader { sweepPressed in
              MaterialButtonEffect.capsuleWithContent(
                baseColor: backgroundColor,
                isPressed: sweepPressed,
                seed: seed
              ) {
                powerLabel
              }
              .allowsHitTesting(false)
            }
          }
          .contentShape(shape)
          .sweepable(
            icon: "power",
            color: .red,
            delay: safetyDelay,
            tooltip: "Hold to power off",
            onSweepComplete: onPower
          )
      )
    }

    static func normalOffView<ButtonContent: View, Label: View>(
      buttonContent: ButtonContent,
      powerLabel: Label,
      backgroundColor: Color,
      seed: UInt64,
      onPower: @escaping () -> Void
    ) -> AnyView {
      _ = buttonContent
      return AnyView(
        Button {
          HapticService.play(.click)
          onPower()
        } label: {
          powerLabel
        }
        .buttonStyle(MaterialButtonEffect.CapsuleStyle(baseColor: backgroundColor, seed: seed))
      )
    }

    // MARK: - Pair helpers

    private static func powerOnOffDevicesInPair(pairState: SafePowerButtonPairState, onPower: () -> Void) {
      guard let tvId = pairState.tvId, let streamerId = pairState.streamerId else {
        onPower()
        return
      }

      let tvOn = pairState.tvMode.isOn
      let streamerOn = (pairState.streamerMode?.isOn ?? false)

      if !tvOn { sendPower(to: tvId) }
      if !streamerOn { sendPower(to: streamerId) }
    }

    private static func powerOffOnDevicesInPair(pairState: SafePowerButtonPairState, onPower: () -> Void) {
      guard let tvId = pairState.tvId, let streamerId = pairState.streamerId else {
        onPower()
        return
      }

      let tvOn = pairState.tvMode.isOn
      let streamerOn = (pairState.streamerMode?.isOn ?? false)

      if tvOn { sendPower(to: tvId) }
      if streamerOn { sendPower(to: streamerId) }
    }

    private static func sendPower(to deviceId: String) {
      Task {
        let device: DeviceInfo? = await MainActor.run {
          let discovery = RokuDiscoveryService.shared
          return discovery.tvs.first { $0.id == deviceId }
            ?? discovery.streamingDevices.first { $0.id == deviceId }
        }
        guard let device else {
          Log.warn("Remote", "Power target not found for id=\(deviceId)")
          return
        }

        _ = await RokuECPClient.shared.sendActionWithResult(.power, to: device)
      }
    }
  }
