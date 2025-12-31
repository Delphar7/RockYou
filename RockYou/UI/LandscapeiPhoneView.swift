//
//  LandscapeiPhoneView.swift
//  RockYou
//
//  Landscape iPhone layout: Left 2x3 grid, D-Pad center, Right 2x3 grid
//

import SwiftUI

struct LandscapeiPhoneView: View {
  let onAction: (RemoteAction) -> Void
  @Binding var showingConfigure: Bool
  @Binding var showingTVSelector: Bool
  let deviceId: String?
  let onLaunchApp: (RokuApp) -> Void
  let selectedTVName: String?
  let selectedStreamerName: String?
  let selectedDeviceId: String?
  let hardwareControlsAvailable: Bool
  var showAppStrip: Bool = true

  @State private var settings = AppSettings.shared

  var body: some View {
    ZStack(alignment: .top) {
      // Main content
      HStack(spacing: 0) {
        // Button section - centered vertically between header bottom and screen bottom
        VStack(spacing: 0) {
          // Top spacer matching header height. Give the main control grid a little extra breathing room.
          Spacer()
            .frame(height: 64)

          // Button section
          HStack {
            // Left side: 2x3 grid (vertical-first)
            leftButtonGrid

            // Center: D-Pad
            DPadView(
              onDirection: { onAction($0) },
              onOK: { onAction(.ok) },
              size: 200
            ).offset(y: -8)

            // Fixed 2pt spacer between D-Pad and right buttons
            Spacer()
              .frame(width: 38)

            // Right side: 2x3 grid (vertical-first)
            rightButtonGrid
          }

          // Bottom spacer to center the button section
          Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)


        Spacer()
        // App strip: 2 columns - ticker that extends beyond edges
        if showAppStrip, let deviceId = deviceId {
          ZStack(alignment: .topTrailing) {
            // App strip - no padding, scrolls naturally like a ticker
            AppStripView(
              deviceId: deviceId,
              direction: .vertical,
              lanes: 2,
              sizing: .fixed(width: 72),
              showLabels: true,
              appLaunchDelay: settings.phoneAppLaunchDelay,
              onLaunch: onLaunchApp
            )

            // Blur Overlay (keeps the strip from visually colliding with the header controls).
            Rectangle()
              .fill(.black)
              .mask(
                LinearGradient(
                  gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(AppOpacity.nearlyOpaque), location: 0.0),
                    .init(color: Color.black.opacity(AppOpacity.secondary), location: 0.70),
                    .init(color: Color.black.opacity(AppOpacity.subtle), location: 1.0),
                  ]),
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
              .frame(maxWidth: .infinity, maxHeight: 85)
              .allowsHitTesting(false)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // Header: Device selector and power button (overlay)
      headerBar
    }
  }

  // MARK: - Header Bar

  private var headerBar: some View {
    RemoteTopBarView(
      scaleFactor: 1,
      edgePadding: 0,
      selectedTVName: selectedTVName,
      selectedStreamerName: selectedStreamerName,
      selectedDeviceId: selectedDeviceId,
      hardwareControlsAvailable: hardwareControlsAvailable,
      showingTVSelector: $showingTVSelector,
      phonePowerDelay: settings.phonePowerDelay,
      onAction: onAction
    )
    .padding(.top, 8)
    .padding(.bottom, 8)
    .background(
      // Subtle background to ensure header is visible over content
      Color.black.opacity(AppOpacity.standard)
    )
  }

  // MARK: - Left Button Grid (Top 5 buttons)

  private var leftButtonGrid: some View {
    HStack(spacing: 28) {  // Increased from 16 to 22 (6pt more)
      // Column 1: Back, Home, Settings
      VStack(spacing: 50) {  // Increased spacing for rectangles only
        TopKeyButton(systemName: "chevron.left", width: 64, height: 50) {
          onAction(.back)
        }
        if let homeDelay = settings.phoneHomeDelay, homeDelay > 0 {
          TopKeyButton(systemName: "house.fill", width: 64, height: 50) {}
            .sweepable(
              icon: "house.fill",
              color: .indigo,
              delay: homeDelay,
              tooltip: "Hold to go home",
              onSweepComplete: { onAction(.home) }
            )
        } else {
          TopKeyButton(systemName: "house.fill", width: 64, height: 50) { onAction(.home) }
        }
        TopKeyButton(systemName: "gearshape.fill", width: 64, height: 50) {
          showingConfigure = true
        }
      }

      // Column 2: Options, spacer frame, Instant Replay
      VStack(spacing: 50) {  // Increased spacing for rectangles only
        TopKeyButton(systemName: "asterisk", width: 64, height: 50, baseColor: rokuDarkPurple) {
          onAction(.options)
        }
        // Spacer frame between Options and Instant Replay
        Spacer()
          .frame(height: 50)
        TopKeyButton(systemName: "gobackward.15", width: 64, height: 50, baseColor: rokuDarkPurple)
        {
          onAction(.instantReplay)
        }
      }
    }
  }

  // MARK: - Right Button Grid (Bottom 6 buttons)

  private var rightButtonGrid: some View {
    HStack(spacing: 28) {  // Increased from 16 to 22 (6pt more)
      // Column 1: Transport controls (Rewind, Play/Pause, Forward)
      VStack(spacing: 32) {  // Keep circular buttons at 32
        CircleKeyButton(systemName: "backward.fill", size: 64, baseColor: rokuDarkPurple) {
          onAction(.rewind)
        }
        CircleKeyButton(systemName: "playpause.fill", size: 72, baseColor: rokuDarkPurple) {
          onAction(.playPause)
        }
        CircleKeyButton(systemName: "forward.fill", size: 64, baseColor: rokuDarkPurple) {
          onAction(.forward)
        }
      }

      // Column 2: Volume controls (Down, Mute, Up)
      VStack(spacing: 50) {  // Increased spacing for rectangles only
        TopKeyButton(systemName: "speaker.plus.fill", width: 64, height: 50) {
          onAction(.volumeUp)
        }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
        TopKeyButton(systemName: "speaker.minus.fill", width: 64, height: 50) {
          onAction(.volumeDown)
        }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
        TopKeyButton(systemName: "speaker.slash.fill", width: 64, height: 50) {
          onAction(.volumeMute)
        }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      }
    }
  }
}
