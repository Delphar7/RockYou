import SwiftUI

@MainActor
enum AppSettingsPlatform {
  static func syncToWatch() {
    // Keep all Watch applicationContext updates centralized in WatchConnectivityManager
    // so we don't duplicate payload shapes and keys.
    WatchConnectivityManager.shared.refreshWatchContext()
  }
}

struct SettingsView: View {
  @Binding var isPresented: Bool
  var doneButtonPlacement: DoneButtonPlacement = .trailing

  @ObservedObject private var watchManager = WatchConnectivityManager.shared
  @State private var configureTVs = ConfigureTVsState()

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
      // Let the system material handle blending; our sheet background is already dark.
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarBackground(.thinMaterial, for: .navigationBar)
      // Prevent touches in "empty" areas of the sheet from routing to sweepables behind it.
      .sweepBlockingZone()
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
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarBackground(.regularMaterial, for: .navigationBar)
      // Prevent touches in "empty" areas of the sheet from routing to sweepables behind it.
      .sweepBlockingZone()
    }
  }

  private var settingsList: some View {
    ZStack {
      List {
        // Configure TVs: scrollable content only (header is unified under the nav bar).
        ConfigureTVsPanel(model: configureTVs)

        SettingsViewCore(
          hasWatch: watchManager.isPaired && watchManager.isWatchAppInstalled,
          watchSection: SettingsWatchSection(
            isPaired: watchManager.isPaired,
            isWatchAppInstalled: watchManager.isWatchAppInstalled,
            openWatchAppSettings: openWatchAppSettings
          ),
          showSafetyDelays: true
        )
      }
      .listStyle(.plain)
      // Make the List background match the sheet background so Materials blend consistently.
      .scrollContentBackground(.hidden)
      .background(Color(white: 0.12))
      // This makes the "Configure TVs / Share" bar a real top bar under the nav bar
      // (not a pinned section header), so it blends seamlessly with the Settings title bar.
      .safeAreaInset(edge: .top, spacing: 0) {
        ConfigureTVsHeaderRow(model: configureTVs)
      }
      .configureTVsDialogs(model: configureTVs)

      // Settings is presented as a sheet above the main root, so we need the overlay
      // mounted inside this host.
      SweepOverlayView()
    }
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
