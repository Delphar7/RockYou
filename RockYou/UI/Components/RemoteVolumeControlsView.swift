import SwiftUI

struct RemoteVolumeControlsView: View {
  let scaleFactor: CGFloat
  let hardwareControlsAvailable: Bool
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor) {
      TopKeyButton(
        systemName: "speaker.slash.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.volumeMute) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      TopKeyButton(
        systemName: "speaker.minus.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.volumeDown) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      TopKeyButton(
        systemName: "speaker.plus.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.volumeUp) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
    }
    .padding(.vertical, RemoteCoreButtonMetrics.topKeyVerticalPadding * scaleFactor)
  }
}
