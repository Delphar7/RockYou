//
//  AppGridView.swift
//  RockYou Watch App
//
//  Fullscreen app picker - navigation container around AppStripView
//

import SwiftUI

struct AppGridView: View {
  let apps: [RokuApp]
  let deviceId: String
  let onSelect: (RokuApp) -> Void
  @Binding var isPresented: Bool
  @State private var settings = WatchAppSettings.shared

  var body: some View {
    NavigationStack {
      AppStripView(
        apps: apps,
        deviceId: deviceId,
        onLaunch: { app in
          onSelect(app)
          isPresented = false
        },
        direction: .vertical,
        lanes: 2,
        sizing: .percent(85),
        showLabels: true,
        appLaunchDelay: settings.watchAppLaunchDelay
      )
      // The global overlay in ContentView is rendered *behind* this sheet.
      // Add overlays here too so tooltips/sweep appear above the sheet content.
      .overlay {
        TooltipOverlayView()
        SweepOverlayView()
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("", systemImage: "xmark") {
            isPresented = false
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Text("Apps")
            .font(.system(size: AppFontSize.large, weight: .semibold))
        }
      }
    }
  }
}

#Preview {
  AppGridView(
    apps: [
      RokuApp(id: "12", name: "Netflix", type: "appl", version: nil, deviceId: "test"),
      RokuApp(id: "13", name: "Prime Video", type: "appl", version: nil, deviceId: "test"),
      RokuApp(id: "837", name: "YouTube", type: "appl", version: nil, deviceId: "test"),
      RokuApp(id: "2285", name: "Hulu", type: "appl", version: nil, deviceId: "test"),
      RokuApp(id: "291097", name: "Disney+", type: "appl", version: nil, deviceId: "test"),
      RokuApp(id: "46041", name: "HDMI 1", type: "tvin", version: nil, deviceId: "test"),
    ],
    deviceId: "test",
    onSelect: { _ in },
    isPresented: .constant(true)
  )
}
