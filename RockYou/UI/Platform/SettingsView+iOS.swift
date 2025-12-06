import SwiftUI

struct SettingsView: View {
  @Binding var isPresented: Bool
  var doneButtonPlacement: DoneButtonPlacement = .trailing

  @ObservedObject private var watchManager = WatchConnectivityManager.shared

  var body: some View {
    if #available(iOS 16.0, *) {
      NavigationStack {
        settingsList
          .navigationTitle("Settings")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(
              placement: doneButtonPlacement == .leading ? .topBarLeading : .topBarTrailing
            ) {
              doneButton
            }
          }
      }
    } else {
      NavigationView {
        settingsList
          .navigationTitle("Settings")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(
              placement: doneButtonPlacement == .leading
                ? .navigationBarLeading : .navigationBarTrailing
            ) {
              doneButton
            }
          }
      }
      .navigationViewStyle(.stack)
    }
  }

  private var settingsList: some View {
    SettingsViewCore(
      isPresented: $isPresented,
      hasWatch: watchManager.isPaired && watchManager.isWatchAppInstalled,
      watchSection: SettingsWatchSection(
        isPaired: watchManager.isPaired,
        isWatchAppInstalled: watchManager.isWatchAppInstalled,
        openWatchAppSettings: openWatchAppSettings
      ),
      listStylePlain: true,
      includeSweepOverlay: true
    )
  }

  private var doneButton: some View {
    Button {
      isPresented = false
    } label: {
      Text("Done")
        .padding(.leading, 12)
        .padding(.trailing, 8)
    }
  }

  private func openWatchAppSettings() {
    // Open the Watch app - this will show available apps to install
    if let watchAppURL = URL(string: "prefs:root=Apple_Watch") {
      if PlatformURLHandler.canOpen(watchAppURL) {
        PlatformURLHandler.open(watchAppURL)
      } else {
        PlatformURLHandler.openAppSettingsFallback()
      }
    }
  }
}
