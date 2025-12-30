//
//  ContentView.swift
//  RockYou
//
//  Created by Delphar Se7en on 11/2/25.
//

import SwiftUI

struct ContentViewCore: View {
  @State private var showingLimitedModeAlert = false
  @State private var limitedModeDeviceName = ""

  /// Platform hook (e.g. haptics). Passed in by `ContentViewHost` platform wrappers.
  private let onPlatformAction: (RemoteAction) -> Void

  init(onPlatformAction: @escaping (RemoteAction) -> Void = { _ in }) {
    self.onPlatformAction = onPlatformAction
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      RemoteControlViewHost(onAction: handleAction)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    .preferredColorScheme(.dark)
    .onOpenURL { url in
      guard let link = DeepLink(url: url) else { return }
      handleDeepLink(link)
    }
    .alert("Device Access Restricted", isPresented: $showingLimitedModeAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(
        "'\(limitedModeDeviceName)' has mobile app control restricted.\n\nTo enable:\nSettings → System → Advanced system settings → Control by mobile apps → Default or Permissive"
      )
    }
  }

  @MainActor
  private func handleDeepLink(_ link: DeepLink) {
    switch link {
    case .selectDevice(let deviceId, _):
      let discovery = RokuDiscoveryService.shared
      if discovery.tvs.contains(where: { $0.id == deviceId }) {
        PairingStore.shared.select(.tv(id: deviceId))
      } else if discovery.streamingDevices.contains(where: { $0.id == deviceId }) {
        PairingStore.shared.select(.streamer(id: deviceId))
      } else {
        Log.warn("DeepLink", "Unknown deviceId=\(deviceId)")
      }
    }
  }

  private func handleAction(_ action: RemoteAction) {
    onPlatformAction(action)

    DebugBuild.run { Log.debug("Remote", "🎮 UI action fired: \(action) key=\(action.ecpKey)") }

    // Send to the selected Roku device
    Task {
      await sendToSelectedDevice(action)
    }
  }

  @MainActor
  private func sendToSelectedDevice(_ action: RemoteAction) async {
    let pairingStore = PairingStore.shared
    let discovery = RokuDiscoveryService.shared

    // If a typed selection exists, prefer it.
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv(let tvId):
        await sendToSelectedTV(action, tvId: tvId, discovery: discovery, pairingStore: pairingStore)
        return
      case .streamer(let streamerId):
        await sendToSelectedStreamer(action, streamerId: streamerId, discovery: discovery)
        return
      }
    }

    // Legacy fallback: selected TV id
    guard let tvId = pairingStore.currentTVId else {
      Log.debug("Remote", "No selection")
      return
    }
    await sendToSelectedTV(action, tvId: tvId, discovery: discovery, pairingStore: pairingStore)
  }

  @MainActor
  private func sendToSelectedStreamer(
    _ action: RemoteAction,
    streamerId: String,
    discovery: RokuDiscoveryService
  ) async {
    // Hardware controls require a TV pairing.
    let isHardwareControl =
      action == .volumeUp || action == .volumeDown
      || action == .volumeMute || action == .power

    if isHardwareControl {
      Log.debug("Remote", "Hardware control unavailable for unpaired streamer selection")
      return
    }

    guard let device = discovery.streamingDevices.first(where: { $0.id == streamerId }) else {
      Log.warn("Remote", "Selected streamer not found on network (streamerId=\(streamerId))")
      return
    }

    DebugBuild.run {
      Log.debug("Remote", "➡️ Sending action=\(action.ecpKey) to streamer name=\(device.name) id=\(device.id)")
    }

    let requiredDevices: [DeviceInfo] = [device]
    let result =
      await RokuECPClient.shared.sendActionInSilo(
        action,
        siloId: streamerId,
        requiredDevices: requiredDevices,
        targetDevice: device
      )
    DebugBuild.run {
      Log.debug(
        "Remote", "⬅️ Send result action=\(action.ecpKey) result=\(String(describing: result))")
    }

    if result == .limitedMode {
      limitedModeDeviceName = device.name
      showingLimitedModeAlert = true
    } else if result == .failed {
      Log.warn("Remote", "Failed to send \(action.ecpKey) to \(device.name)")
    }
  }

  @MainActor
  private func sendToSelectedTV(
    _ action: RemoteAction,
    tvId: String,
    discovery: RokuDiscoveryService,
    pairingStore: PairingStore
  ) async {

    let streamerId = pairingStore.streamerIdForTV(tvId)
    DebugBuild.run {
      Log.debug(
        "Remote",
        "Routing action=\(action) key=\(action.ecpKey) tvId=\(tvId) streamerId=\(streamerId ?? "nil") tvs=\(discovery.tvs.count) streamers=\(discovery.streamingDevices.count)"
      )
    }

    // Volume and Power ALWAYS go to the TV (streamer can't control TV hardware)
    let isHardwareControl =
      action == .volumeUp || action == .volumeDown
      || action == .volumeMute || action == .power

    let targetDevice: DeviceInfo?

    if isHardwareControl {
      // Volume/Power → TV directly
      targetDevice = discovery.tvs.first { $0.id == tvId }
    } else if let streamerId {
      // Navigation/Playback → Streamer (if paired)
      targetDevice = discovery.streamingDevices.first { $0.id == streamerId }
    } else {
      // No streamer → TV's built-in Roku
      targetDevice = discovery.tvs.first { $0.id == tvId }
    }

    guard let device = targetDevice else {
      Log.warn(
        "Remote",
        "Target device not found on network (tvId=\(tvId), streamerId=\(streamerId ?? "nil"))")
      return
    }

    // Required devices for "wake-gated" actions:
    // - Always include the TV.
    // - Include the paired streamer (if present) so the "pair" wakes as a unit.
    var requiredDevices: [DeviceInfo] = []
    if let tv = discovery.tvs.first(where: { $0.id == tvId }) {
      requiredDevices.append(tv)
    }
    if let streamerId, let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId }) {
      requiredDevices.append(streamer)
    }

    DebugBuild.run {
      Log.debug(
        "Remote",
        "➡️ Sending action=\(action.ecpKey) to device name=\(device.name) id=\(device.id) ip=\(device.ipAddress)"
      )
    }
    let result =
      await RokuECPClient.shared.sendActionInSilo(
        action,
        siloId: tvId,
        requiredDevices: requiredDevices,
        targetDevice: device
      )
    DebugBuild.run {
      Log.debug(
        "Remote", "⬅️ Send result action=\(action.ecpKey) result=\(String(describing: result))")
    }

    if result == .limitedMode {
      // Show user guidance for restricted device
      limitedModeDeviceName = device.name
      showingLimitedModeAlert = true
    } else if result == .failed {
      Log.warn("Remote", "Failed to send \(action.ecpKey) to \(device.name)")
    }
    // .success and .unreachable are handled silently (state updated by ECP client)
  }

}

#Preview {
  ContentViewHost()
}
