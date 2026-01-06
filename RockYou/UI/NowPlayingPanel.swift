//
//  NowPlayingPanel.swift
//  RockYou
//
//  Right-side info panel for landscape iPad/Mac showing device info and now playing.
//  Also provides split components for iPad portrait mode.
//

import SwiftUI

// MARK: - Main Panel (Landscape)

@MainActor
struct NowPlayingPanel: View {
  let deviceId: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      InfoTopPanel(deviceId: deviceId)

      InfoBottomPanel(deviceId: deviceId)

      // Flexible spacer: pushes content up when there's excess height.
      // In a ScrollView this is effectively zero (minLength: 0).
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

// MARK: - Top Panel Component (Device Header + Now Playing)

@MainActor
struct InfoTopPanel: View {
  let deviceId: String?

  var body: some View {
    // Access shared observables directly in body so SwiftUI tracks @Observable changes
    let stateManager = DeviceStateManager.shared
    let discovery = RokuDiscoveryService.shared
    let appCache = AppCacheManager.shared

    let currentState: DeviceState? = deviceId.map { id in
      stateManager.states[id] ?? DeviceState()
    }

    let _ = appCache.iconVersion

    let currentDevice = deviceId.flatMap { id in
      discovery.discoveredDevices.first { $0.id == id }
    }

    VStack(alignment: .leading, spacing: 24) {
      // Now playing section (top)
      if let deviceId = deviceId, let state = currentState {
        nowPlayingSection(deviceId: deviceId, state: state, appCache: appCache)
      }

      Divider()
        .background(Color.white.opacity(0.2))

      // Device info header (bottom)
      if let device = currentDevice {
        let deviceState = stateManager.state(for: device.id)
        deviceHeader(device, state: deviceState)
      } else {
        noDeviceView
      }
    }
  }
}

// MARK: - Bottom Panel Component (Device State)

@MainActor
struct InfoBottomPanel: View {
  let deviceId: String?
  @State private var macAddresses: [(label: String, value: String)] = []

  var body: some View {
    let stateManager = DeviceStateManager.shared
    let discovery = RokuDiscoveryService.shared

    let currentState: DeviceState? = deviceId.map { id in
      stateManager.states[id] ?? DeviceState()
    }

    let currentDevice = deviceId.flatMap { id in
      discovery.discoveredDevices.first { $0.id == id }
    }

    if let deviceId = deviceId, let state = currentState {
      deviceStateSection(
        deviceId: deviceId, state: state, currentDevice: currentDevice, macAddresses: macAddresses
      )
      .task {
        // Fetch MAC addresses asynchronously
        if let device = currentDevice {
          let ecpClient = RokuECPClient.shared
          if let deviceInfo = await ecpClient.fetchDeviceInfoFieldsECP2(for: device) {
            var macs: [(label: String, value: String)] = []

            // Collect all MAC addresses
            if let wifiMac = deviceInfo["wifi-mac"], !wifiMac.isEmpty {
              macs.append((label: "Wi-Fi MAC", value: wifiMac))
            }
            if let ethernetMac = deviceInfo["ethernet-mac"], !ethernetMac.isEmpty {
              macs.append((label: "Wired MAC", value: ethernetMac))
            }

            // Check for any other MAC addresses (unlikely, but handle it)
            for (key, value) in deviceInfo {
              if key.contains("mac") && key != "wifi-mac" && key != "ethernet-mac" && !value.isEmpty
              {
                macs.append((label: key, value: value))
              }
            }

            // If only one MAC, use simple "MAC" label
            if macs.count == 1 {
              macs[0] = (label: "MAC", value: macs[0].value)
            }

            macAddresses = macs
          }
        }
      }
    }
  }
}

// MARK: - Shared Helper Views

extension InfoTopPanel {
  @ViewBuilder
  func deviceHeader(_ device: DeviceInfo, state: DeviceState) -> some View {
    HStack(alignment: .top, spacing: 16) {
      // Device icon (no status dot)
      if device.isTV {
        RokuTVIcon(size: 48, screenColor: state.powerMode.statusColor)
      } else {
        StreamingDeviceIcon(size: 48, bodyColor: state.powerMode.statusColor)
      }

      VStack(alignment: .leading, spacing: 6) {
        // Primary name
        Text(device.name)
          .font(.title2.weight(.semibold))
          .foregroundStyle(.white)

        // Location/alias if different from name
        if let location = device.location, location != device.name {
          Text(location)
            .font(.headline)
            .foregroundStyle(.white.opacity(AppOpacity.primary))
        }

        // Power state (hoisted up)
        HStack(spacing: 6) {
          Circle()
            .fill(state.powerMode.statusColor)
            .frame(width: 10, height: 10)
          Text(state.powerMode.displayName)
            .font(.subheadline)
            .foregroundStyle(state.powerMode.statusColor)
        }
      }

      Spacer()

      // Right side: Model/type and ID
      VStack(alignment: .trailing, spacing: 4) {
        // Model and device type
        HStack(spacing: 8) {
          if let model = device.model {
            Text(model)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(AppOpacity.primary))
          }
          Text(device.deviceType.rawValue)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(AppOpacity.primary))
        }

        // Device ID (serial number)
        Text("ID: \(device.id)")
          .font(.caption.monospaced())
          .foregroundStyle(.white.opacity(AppOpacity.secondary))
      }
    }
  }

  var noDeviceView: some View {
    VStack(spacing: 12) {
      Image(systemName: "tv.slash")
        .font(.system(size: AppFontSize.iconLarge))
        .foregroundStyle(.secondary)
      Text("No Device Selected")
        .font(.headline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
  }

  @ViewBuilder
  func nowPlayingSection(deviceId: String, state: DeviceState, appCache: AppCacheManager) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      if let activeAppId = state.activeApp,
         let app = appCache.apps(for: deviceId).first(where: { $0.id == activeAppId }) {
        // Active app with icon
        VStack(alignment: .leading, spacing: 12) {
          // App icon (use the same input-centering treatment as AppStrip)
          let isInputIcon = AppIconClassifier.isInput(appId: activeAppId, appType: app.type)
          let treatment: AppIconTreatment = {
            if isInputIcon {
              // The app name is shown elsewhere in this panel (outside the icon),
              // so center the *real* input panel and avoid the baked-in bottom strip reading as a "divider line".
              return .inputCenterByPanel()
            }
            // In this info panel we prefer to see the whole icon rather than cropping to fill a square tile.
            return .normalFit
          }()

          let iconCornerRadius: CGFloat = 12
          // Use a consistent 4×3 tile here so icon rendering matches the AppStrip geometry.
          let iconSize = CGSize(width: 120, height: 90)

          HStack(spacing: 16) {
            Spacer()
            AppIcon(
              image: appCache.iconImage(for: activeAppId, deviceId: deviceId),
              size: iconSize,
              cornerRadius: iconCornerRadius,
              treatment: treatment
            ) {
              RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                .fill(Color.gray.opacity(AppOpacity.standard))
                .overlay(
                  Image(systemName: "app.fill")
                    .font(.system(size: AppFontSize.iconSmall))
                    .foregroundStyle(.secondary)
                )
            }
            Spacer()
          }.padding(.bottom, -32)

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              VStack(alignment: .leading, spacing: 8) {
                Text(app.name)
                  .font(.title3.weight(.medium))
                  .foregroundStyle(.white)

                // Media state (lifted up)
                HStack(spacing: 8) {
                  Image(systemName: state.mediaState.iconName)
                    .foregroundStyle(state.mediaState.color)
                  Text(state.mediaState.displayName)
                    .foregroundStyle(.white.opacity(AppOpacity.primary))
                }
                .font(.subheadline)
              }

              Spacer()

              // Volume (moved up from State Information panel)
              VStack(alignment: .trailing, spacing: 6) {
                let isMutedLike = state.muted || state.volume == 0
                HStack(spacing: 8) {
                  Image(systemName: isMutedLike ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(isMutedLike ? .yellow : .white.opacity(0.8))
                    .font(.system(size: AppFontSize.veryLarge, weight: .semibold))
                  Text(isMutedLike ? "Muted" : "\(state.volume)%")
                    .foregroundStyle(isMutedLike ? .yellow : .white.opacity(AppOpacity.primary))
                    .font(.caption.monospaced())
                }
              }
            }

            // Media position and duration (if available)
            if state.mediaPosition != nil, let duration = state.mediaDuration, duration > 0
            {
              NowPlayingProgressView(state: state, style: .fullPanel)
            } else if let duration = state.mediaDuration, duration > 0 {
              // Duration only (no position)
              Text("Duration: \(formatTime(milliseconds: duration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
        }
      } else {
        // No active app
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.gray.opacity(AppOpacity.medium))
              .frame(width: 120, height: 90)
              .overlay(
                Image(systemName: "tv")
                  .font(.system(size: AppFontSize.iconSmall))
                  .foregroundStyle(.tertiary)
              )

            Text("Now Playing")
              .font(.headline)
              .foregroundStyle(.secondary)
          }

          Text("Home Screen")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  // Helper to format milliseconds as time string
  private func formatTime(milliseconds: Int) -> String {
    let totalSeconds = milliseconds / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

extension InfoBottomPanel {
  @ViewBuilder
  func deviceStateSection(
    deviceId: String, state: DeviceState, currentDevice: DeviceInfo?,
    macAddresses: [(label: String, value: String)]
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // State Information Section
      VStack(alignment: .leading, spacing: 8) {
        Text("State Information")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(AppOpacity.secondary))
          .textCase(.uppercase)

        // App ID + type (moved down from the media panel).
        // Note: these should *share a row* with the position/duration rows (trailing aligned),
        // not consume an extra vertical line that can push the AppStrip off-screen.
        let appCache = AppCacheManager.shared
        let _ = appCache.iconVersion
        let activeApp = state.activeApp.flatMap { id in
          appCache.apps(for: deviceId).first(where: { $0.id == id })
        }
        let appInfo: AnyView? = {
          guard let activeApp else { return nil }
          return AnyView(
            VStack(alignment: .trailing, spacing: 2) {
              Text("App ID: \(activeApp.id)")
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(AppOpacity.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
              if let type = activeApp.type {
                Text("Type: \(type)")
                  .font(.caption)
                  .foregroundStyle(.white.opacity(AppOpacity.secondary))
                  .lineLimit(1)
              }
            }
          )
        }()

        // Media Position/Duration
        // If we have app info, attach it to the first available time row.
        let attachAppInfoToPositionRow = (appInfo != nil && state.mediaPosition != nil)
        let attachAppInfoToDurationRow =
          (appInfo != nil && state.mediaPosition == nil && state.mediaDuration != nil)
        let showStandaloneAppInfoRow =
          (appInfo != nil && state.mediaPosition == nil && state.mediaDuration == nil)
        if let position = state.mediaPosition {
          HStack(spacing: 12) {
            Image(systemName: "clock")
              .foregroundStyle(.white.opacity(AppOpacity.primary))
              .frame(width: 24)
            Text("Position: \(formatTime(milliseconds: position))")
              .foregroundStyle(.white.opacity(AppOpacity.primary))
              .font(.caption.monospaced())
            Spacer()
            if attachAppInfoToPositionRow { appInfo }
          }
        }
        if let duration = state.mediaDuration {
          HStack(spacing: 12) {
            Image(systemName: "timer")
              .foregroundStyle(.white.opacity(AppOpacity.primary))
              .frame(width: 24)
            Text("Duration: \(formatTime(milliseconds: duration))")
              .foregroundStyle(.white.opacity(AppOpacity.primary))
              .font(.caption.monospaced())
            Spacer()
            if attachAppInfoToDurationRow { appInfo }
          }
        }
        if showStandaloneAppInfoRow, let appInfo {
          HStack(spacing: 12) {
            Spacer()
            appInfo
          }
        }
      }

      Divider()
        .background(Color.white.opacity(0.2))

      // Network Information Section
      if let device = currentDevice {
        VStack(alignment: .leading, spacing: 8) {
          Text("Network Information")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(AppOpacity.secondary))
            .textCase(.uppercase)

          HStack(alignment: .top, spacing: 12) {
            // Left side: IP and Subnet
            VStack(alignment: .leading, spacing: 12) {
              // IP Address
              HStack(spacing: 12) {
                Image(systemName: "network")
                  .foregroundStyle(.white.opacity(AppOpacity.primary))
                  .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                  Text("IP Address")
                    .foregroundStyle(.white.opacity(AppOpacity.secondary))
                    .font(.caption)
                  Text(device.ipAddress)
                    .foregroundStyle(.white.opacity(AppOpacity.primary))
                    .font(.subheadline.monospaced())
                  if device.port != 8060 {
                    Text("Port: \(device.port)")
                      .foregroundStyle(.white.opacity(AppOpacity.secondary))
                      .font(.caption.monospaced())
                  }
                }
              }

              // Subnet Mask
              if let subnetMask = NetworkInfoProvider.subnetMask(for: device.ipAddress) {
                HStack(spacing: 12) {
                  Image(systemName: "network.badge.shield.half.filled")
                    .foregroundStyle(.white.opacity(AppOpacity.primary))
                    .frame(width: 24)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Subnet")
                      .foregroundStyle(.white.opacity(AppOpacity.secondary))
                      .font(.caption)
                    Text(subnetMask)
                      .foregroundStyle(.white.opacity(AppOpacity.primary))
                      .font(.subheadline.monospaced())
                  }
                }
              }
            }

            Spacer()

            // Right side: MAC Address(es)
            if !macAddresses.isEmpty {
              VStack(alignment: .trailing, spacing: 12) {
                ForEach(Array(macAddresses.enumerated()), id: \.offset) { _, mac in
                  VStack(alignment: .trailing, spacing: 2) {
                    Text(mac.label)
                      .foregroundStyle(.white.opacity(AppOpacity.secondary))
                      .font(.caption)
                    Text(mac.value)
                      .foregroundStyle(.white.opacity(AppOpacity.primary))
                      .font(.subheadline.monospaced())
                  }
                }
              }
            }
          }

          // Last Seen (if available)
          if let lastSeen = device.lastSeen {
            HStack(alignment: .bottom, spacing: 12) {
              Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.white.opacity(AppOpacity.secondary))
                .frame(width: 24)
              Text("Last Seen: \(formatDate(lastSeen))")
                .foregroundStyle(.white.opacity(AppOpacity.secondary))
                .font(.caption)
              Spacer()
            }
          }
        }
      }
    }
    .padding(16)
    .background(Color.white.opacity(AppOpacity.verySubtle))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func powerModeIcon(_ mode: PowerMode) -> String {
    switch mode {
    case .on: return "power"
    case .off: return "power"
    case .ready: return "moon.fill"
    case .displayOff: return "display"
    case .unknown: return "questionmark.circle"
    }
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func formatTime(milliseconds: Int) -> String {
    let totalSeconds = milliseconds / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

// MARK: - DeviceState Extensions

extension DeviceState.MediaState {
  var iconName: String {
    switch self {
    case .play: return "play.fill"
    case .pause: return "pause.fill"
    case .stop: return "stop.fill"
    case .idle: return "stop.fill"
    }
  }

  var color: Color {
    switch self {
    case .play: return .green
    case .pause: return .yellow
    case .stop: return .orange
    case .idle: return .secondary
    }
  }

  var displayName: String {
    switch self {
    case .play: return "Playing"
    case .pause: return "Paused"
    case .stop: return "Stopped"
    case .idle: return "Idle"
    }
  }
}

extension PowerMode {
  var displayName: String {
    switch self {
    case .on: return "On"
    case .off: return "Off"
    case .ready: return "Ready"
    case .displayOff: return "Display Off"
    case .unknown: return "Unknown"
    }
  }
}
