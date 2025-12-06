import SwiftUI

struct RemoteLandscapeCompactLayoutView: View {
  let selectedDeviceId: String?
  let selectedTVName: String?
  let selectedStreamerName: String?
  @Binding var showingConfigure: Bool
  @Binding var showingTVSelector: Bool
  let onAction: (RemoteAction) -> Void
  let onLaunchApp: (RokuApp) -> Void
  let hardwareControlsAvailable: Bool

  var body: some View {
    LandscapeiPhoneView(
      onAction: onAction,
      showingConfigure: $showingConfigure,
      showingTVSelector: $showingTVSelector,
      deviceId: selectedDeviceId,
      onLaunchApp: onLaunchApp,
      selectedTVName: selectedTVName,
      selectedStreamerName: selectedStreamerName,
      selectedDeviceId: selectedDeviceId,
      hardwareControlsAvailable: hardwareControlsAvailable
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
