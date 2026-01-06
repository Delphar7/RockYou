import SwiftUI

struct RemotePortraitExpandedLayoutView: View {
  let fullHeight: CGFloat
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
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        InfoTopPanel(deviceId: selectedDeviceId)
          .frame(height: fullHeight / 3)
          .padding(16)

        Divider()
          .background(Color.white.opacity(AppOpacity.subtle))

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
        .frame(height: fullHeight / 3)

        Divider()
          .background(Color.white.opacity(AppOpacity.subtle))
          .padding(.bottom, 16)

        InfoBottomPanel(deviceId: selectedDeviceId)
          .frame(height: fullHeight / 3)
          .padding(16)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()
        .background(Color.white.opacity(0.1))

      AppStripPaneView(
        mode: .portraitExpanded,
        deviceId: selectedDeviceId,
        appLaunchDelay: AppSettings.shared.phoneAppLaunchDelay,
        onLaunchApp: onLaunchApp
      )
    }
  }
}
