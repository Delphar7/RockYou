import SwiftUI

/// Shared "app strip as a right-side pane" renderer used by:
/// - iPhone landscape compact
/// - iPad portrait expanded (right pane)
///
/// This keeps the app-strip wiring/layout consistent; only `LayoutMode` determines config.
struct AppStripPaneView: View {
  let mode: LayoutMode
  let deviceId: String?
  let appLaunchDelay: TimeInterval?
  let onLaunchApp: (RokuApp) -> Void

  var body: some View {
    if let deviceId {
      let config = AppStripConfig.config(for: mode)
      AppStripView(
        deviceId: deviceId,
        direction: config.direction,
        lanes: config.lanes,
        sizing: config.sizing,
        showLabels: config.showLabels,
        appLaunchDelay: appLaunchDelay,
        onLaunch: onLaunchApp
      )
      .frame(maxHeight: .infinity)
      .padding(config.padding)
    }
  }
}
