import SwiftUI

struct RemoteVolumeControlsView: View {
  let scaleFactor: CGFloat
  let hardwareControlsAvailable: Bool
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: 32 * scaleFactor) {
      TopKeyButton(
        systemName: "speaker.slash.fill", width: 72 * scaleFactor, height: 54 * scaleFactor
      ) { onAction(.volumeMute) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      TopKeyButton(
        systemName: "speaker.minus.fill", width: 72 * scaleFactor, height: 54 * scaleFactor
      ) { onAction(.volumeDown) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      TopKeyButton(
        systemName: "speaker.plus.fill", width: 72 * scaleFactor, height: 54 * scaleFactor
      ) { onAction(.volumeUp) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
    }
    .padding(.top, 12 * scaleFactor)
  }
}
