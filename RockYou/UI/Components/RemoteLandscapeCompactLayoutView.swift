import SwiftUI

struct RemoteLandscapeCompactLayoutView: View {
  let selectedDeviceId: String?
  let selectedTVName: String?
  let selectedStreamerName: String?
  @Binding var showingConfigure: Bool
  @Binding var showingTVSelector: Bool
  let onAction: (RemoteAction) -> Void
  let onKeyboard: () -> Void
  let isKeyboardShown: Bool
  let onLaunchApp: (RokuApp) -> Void
  let hardwareControlsAvailable: Bool

  var body: some View {
    let paneGap: CGFloat = 12

    HStack(spacing: paneGap) {
      LandscapeiPhoneView(
        onAction: onAction,
        onKeyboard: onKeyboard,
        isKeyboardShown: isKeyboardShown,
        showingConfigure: $showingConfigure,
        showingTVSelector: $showingTVSelector,
        selectedTVName: selectedTVName,
        selectedStreamerName: selectedStreamerName,
        selectedDeviceId: selectedDeviceId,
        hardwareControlsAvailable: hardwareControlsAvailable
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      AppStripPaneView(
        mode: .landscapeCompact,
        deviceId: selectedDeviceId,
        appLaunchDelay: AppSettings.shared.phoneAppLaunchDelay,
        onLaunchApp: onLaunchApp
      )
    }
  }
}
