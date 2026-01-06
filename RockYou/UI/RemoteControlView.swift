//
//  RemoteControlView.swift
//  RockYou
//
//  Main remote control UI with D-pad, transport, and volume controls.
//  Landscape (iPad/Mac): Remote on left, info panel on right, app strip full width.
//

import SwiftUI

@MainActor
struct RemoteControlView: View {
  private static let docsURL: URL = {
    guard let url = URL(string: "https://jtr.sh/RockYou/docs/") else {
      preconditionFailure("Invalid docs URL")
    }
    return url
  }()

  @State private var settings = AppSettings.shared
  let onAction: (RemoteAction) -> Void
  let windowIsActive: Bool

  @State private var showingConfigure = false
  @State private var showingTVSelector = false
  @State private var showingHelp = false
  @State private var showingKeyboard = false
  @State private var keyboardWasAutoPresented = false
  @State private var keyboardSuppressedWhileTextEditActive = false
  @FocusState private var isFocused: Bool
  @State private var containerSize: CGSize = .zero

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.scenePhase) private var scenePhase

  private var pairingStore: PairingStore { PairingStore.shared }
  private var discovery: RokuDiscoveryService { RokuDiscoveryService.shared }

  private var selection: RemoteControlSelection {
    RemoteControlSelection(pairingStore: pairingStore, discovery: discovery)
  }

  // MARK: - Unified Layout Detection

  /// Unified layout mode detection
  private var layoutMode: LayoutMode {
    RemoteControlPlatform.layoutMode(
      containerSize: containerSize, horizontalSizeClass: horizontalSizeClass)
  }

  /// Scale factor for controls (Mac is 15% smaller)
  private var scaleFactor: CGFloat {
    RemoteControlPlatform.scaleFactor(containerSize: containerSize, layoutMode: layoutMode)
  }

  var body: some View {
    GeometryReader { geometry in
      let textEditStatus = RokuTextEditStateManager.shared.status(for: selection.selectedDeviceId)
      ZStack(alignment: .top) {
        // Main layout based on unified layout mode
        mainLayout(in: geometry)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Sweep overlays (tooltip + sweep animation)
        TooltipOverlayView()
        SweepOverlayView()
      }
      .overlayPreferenceValue(TVSelectorBarBoundsKey.self) { barBounds in
        Group {
          if showingTVSelector, let barBounds {
            TVSelectorDropdown(
              isShowing: $showingTVSelector,
              isPresentingConfigure: $showingConfigure,
              isPresentingHelp: $showingHelp,
              barBounds: barBounds
            )
          }
        }
      }
      .onAppear {
        containerSize = geometry.size
        Task { await updateActiveStatePollingEnablement() }
      }
      .onChange(of: textEditStatus.isActive) { _, isActive in
        // Parity with Roam: if Roku reports an active text field, auto-present keyboard entry.
        // If the field closes, auto-dismiss only if it was auto-presented.
        if isActive {
          if !showingKeyboard {
            if !keyboardSuppressedWhileTextEditActive {
              keyboardWasAutoPresented = true
              showingKeyboard = true
              Log.debug("Keyboard", "Auto-present keyboard (textedit active)")
            }
          }
        } else {
          keyboardSuppressedWhileTextEditActive = false
          if keyboardWasAutoPresented {
            keyboardWasAutoPresented = false
            showingKeyboard = false
            Log.debug("Keyboard", "Auto-dismiss keyboard (textedit inactive)")
          }
        }
      }
      .onChange(of: showingKeyboard) { _, isShowing in
        // If the user hides the keyboard UI while the text field is still active on Roku,
        // do not immediately re-open it. Keep it suppressed until the text field goes inactive.
        if !isShowing, textEditStatus.isActive {
          keyboardSuppressedWhileTextEditActive = true
          keyboardWasAutoPresented = false
          Log.debug("Keyboard", "User dismissed keyboard while textedit active (suppressing auto-present)")
        }
        if isShowing {
          keyboardSuppressedWhileTextEditActive = false
        }
      }
      // Intentionally do not force focus changes here; iOS software keyboard visibility
      // is primarily controlled by (a) first-responder focus and (b) the simulator
      // "Connect Hardware Keyboard" setting. Forcing focus here can make debugging harder.
      .onChange(of: scenePhase) { _, newValue in
        Task { await updateActiveStatePollingEnablement(phase: newValue) }
      }
      .onChange(of: selection.selectedDeviceId) { _, newDeviceId in
        Task { await updateActiveStatePollingEnablement(selectedDeviceId: newDeviceId) }
      }
      .onChange(of: geometry.size) { _, newSize in
        containerSize = newSize
      }
    }
    // Foreground gating for AppIconWithLabel glow animations
    .environment(\.glowAnimationForegroundEnabled, glowAnimationForegroundEnabled)
    .contentShape(Rectangle())
    .focusable()
    .focused($isFocused)
    .focusEffectDisabled()
    .platformRemoteSurface(isActive: windowIsActive)
    .remoteControlKeyPresses(onAction: onAction)
    .platformSettingsPresentation(
      isPresented: $showingConfigure,
      sheet: { SettingsView(isPresented: $showingConfigure) },
      panel: { SettingsView(isPresented: $showingConfigure, doneButtonPlacement: .leading) },
      inspector: {
        SettingsView(isPresented: $showingConfigure)
          .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
      }
    )
    .platformHelpPresentation(isPresented: $showingHelp, url: Self.docsURL)
    .sheet(isPresented: $showingKeyboard) {
      RemoteKeyboardEntryView(target: keyboardTarget())
    }
    .task(id: selection.selectedDeviceIP) {
      // Connect to selected device to get state updates
      await connectToSelectedDevice()
    }
  }

  private var glowAnimationForegroundEnabled: Bool {
    RemoteControlPlatform.glowAnimationForegroundEnabled(
      scenePhase: scenePhase, windowIsActive: windowIsActive)
  }

  // MARK: - Layout Views

  private func tvSelectorTapped() {
    withAnimation(.easeInOut(duration: 0.2)) {
      showingTVSelector.toggle()
    }
  }

  private func keyboardTapped() {
    keyboardWasAutoPresented = false
    if showingKeyboard {
      showingKeyboard = false
    } else {
      keyboardSuppressedWhileTextEditActive = false
      showingKeyboard = true
    }
  }

  struct KeyboardTarget: Sendable {
    let siloId: String
    let requiredDevices: [DeviceInfo]
    let targetDevice: DeviceInfo
  }

  private func keyboardTarget() -> KeyboardTarget? {
    let pairingStore = PairingStore.shared
    let discovery = RokuDiscoveryService.shared

    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv(let tvId):
        guard let target = self.selection.selectedDevice else { return nil }
        var required: [DeviceInfo] = []
        if let tv = discovery.tvs.first(where: { $0.id == tvId }) { required.append(tv) }
        if let streamerId = pairingStore.streamerIdForTV(tvId),
           let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId }) {
          required.append(streamer)
        }
        return KeyboardTarget(siloId: tvId, requiredDevices: required, targetDevice: target)
      case .streamer(let streamerId):
        guard let device = discovery.streamingDevices.first(where: { $0.id == streamerId }) else { return nil }
        return KeyboardTarget(siloId: streamerId, requiredDevices: [device], targetDevice: device)
      }
    }

    // Legacy fallback: selected TV id
    guard let tvId = pairingStore.currentTVId else { return nil }
    guard let target = self.selection.selectedDevice else { return nil }
    var required: [DeviceInfo] = []
    if let tv = discovery.tvs.first(where: { $0.id == tvId }) { required.append(tv) }
    if let streamerId = pairingStore.streamerIdForTV(tvId),
       let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId }) {
      required.append(streamer)
    }
    return KeyboardTarget(siloId: tvId, requiredDevices: required, targetDevice: target)
  }

  @ViewBuilder
  private func mainLayout(in geometry: GeometryProxy) -> some View {
    VStack(spacing: 0) {
      switch layoutMode {
      case .portraitExpanded:
        RemotePortraitExpandedLayoutView(
          fullHeight: geometry.size.height,
          selectedDeviceId: selection.selectedDeviceId,
          selectedTVName: selection.selectedTVName,
          selectedStreamerName: selection.selectedStreamerName,
          showingConfigure: $showingConfigure,
          showingTVSelector: $showingTVSelector,
          onAction: onAction,
          onKeyboard: keyboardTapped,
          isKeyboardShown: showingKeyboard,
          onLaunchApp: { app in launchApp(app) },
          hardwareControlsAvailable: selection.hardwareControlsAvailable
        )
      case .landscapeCompact:
        RemoteLandscapeCompactLayoutView(
          selectedDeviceId: selection.selectedDeviceId,
          selectedTVName: selection.selectedTVName,
          selectedStreamerName: selection.selectedStreamerName,
          showingConfigure: $showingConfigure,
          showingTVSelector: $showingTVSelector,
          onAction: onAction,
          onKeyboard: keyboardTapped,
          isKeyboardShown: showingKeyboard,
          onLaunchApp: { app in launchApp(app) },
          hardwareControlsAvailable: selection.hardwareControlsAvailable
        )
      case .landscapeSplit:
        VStack(spacing: 0) {
          splitLayoutView(deviceId: selection.selectedDeviceId)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          bottomAppStripContent()
        }
      case .portraitCompact:
        let shouldRenderBottomTicker = true
        RemotePortraitCompactLayoutView(
          containerSize: geometry.size,
          renderBottomTicker: shouldRenderBottomTicker,
          selectedTVName: selection.selectedTVName,
          selectedStreamerName: selection.selectedStreamerName,
          selectedDeviceId: selection.selectedDeviceId,
          hardwareControlsAvailable: selection.hardwareControlsAvailable,
          showingConfigure: $showingConfigure,
          showingTVSelector: $showingTVSelector,
          isKeyboardShown: showingKeyboard,
          onKeyboard: keyboardTapped,
          phonePowerDelay: settings.phonePowerDelay,
          phoneHomeDelay: settings.phoneHomeDelay,
          appLaunchDelay: settings.phoneAppLaunchDelay,
          onAction: onAction,
          onLaunchApp: { app in launchApp(app) }
        )
      }
    }
  }

  @ViewBuilder
  private func bottomAppStripContent() -> some View {
    if let deviceId = selection.selectedDeviceId {
      let config = AppStripConfig.config(for: layoutMode)
      if config.isVisible {
        let stripScale =
          RemoteControlPlatform.appStripScaleFactor(
            containerSize: containerSize, layoutMode: layoutMode)
        let scaledSizing = config.sizing?.scaled(by: stripScale)
        let horizontalInset = RemoteControlPlatform.appStripHorizontalInset(layoutMode: layoutMode)

        VStack(spacing: 0) {
          AppStripView(
            deviceId: deviceId,
            direction: config.direction,
            lanes: RemoteControlPlatform.appStripLanesOverride(
              layoutMode: layoutMode,
              direction: config.direction
            ) ?? config.lanes,
            sizing: scaledSizing,
            showLabels: config.showLabels,
            appLaunchDelay: settings.phoneAppLaunchDelay,
            onLaunch: { app in launchApp(app) }
          )
          .padding(config.padding)
          .padding(.horizontal, horizontalInset)
        }
      }
    }
  }

  // MARK: - Shared Layout Components

  /// Split layout: Remote controls on left, Info panel on right
  /// Used by: iPad landscape, Mac fat window
  @ViewBuilder
  private func splitLayoutView(deviceId: String?) -> some View {
    HStack(spacing: 0) {
      // Use the experiment renderer for the left pane too (no toggle).
      // Bottom ticker remains owned by `RemoteControlView` so it spans both panes.
      RemotePortraitCompactLayoutView(
        containerSize: containerSize,
        renderBottomTicker: false,
        selectedTVName: selection.selectedTVName,
        selectedStreamerName: selection.selectedStreamerName,
        selectedDeviceId: selection.selectedDeviceId,
        hardwareControlsAvailable: selection.hardwareControlsAvailable,
        showingConfigure: $showingConfigure,
        showingTVSelector: $showingTVSelector,
        isKeyboardShown: showingKeyboard,
        onKeyboard: keyboardTapped,
        phonePowerDelay: settings.phonePowerDelay,
        phoneHomeDelay: settings.phoneHomeDelay,
        appLaunchDelay: settings.phoneAppLaunchDelay,
        onAction: onAction,
        onLaunchApp: { app in launchApp(app) }
      )
      .frame(maxWidth: .infinity)

      Divider()
        .background(Color.white.opacity(0.1))

      NowPlayingPanel(deviceId: deviceId)
        .frame(maxWidth: .infinity)
    }
  }

  // (Old `RemoteControlsSectionView` compact renderer removed; the portrait layout is now
  // implemented by `RemotePortraitCompactLayoutView`.)

  // MARK: - Device Connection

  private func connectToSelectedDevice() async {
    guard let ip = selection.selectedDeviceIP else {
      await RokuECPClient.shared.setMediaProgressEnabledDeviceIds([])
      await RokuECPClient.shared.setAppListRefreshEnabledDeviceIds([])
      await RokuECPClient.shared.setActiveStatePollingEnabledDeviceIds([])
      Log.warn("Remote", "No selected device IP")
      return
    }

    // Find the device and try to connect
    let device = discovery.discoveredDevices.first { $0.ipAddress == ip }
    if let device = device {
      await RokuECPClient.shared.setMediaProgressEnabledDeviceIds([device.id])
      await RokuECPClient.shared.setAppListRefreshEnabledDeviceIds([device.id])
      let shouldEnable = RemoteControlPlatform.shouldEnableActiveStatePolling(
        scenePhase: scenePhase,
        selectedDeviceId: device.id
      )
      await RokuECPClient.shared.setActiveStatePollingEnabledDeviceIds(
        shouldEnable ? [device.id] : [])
      let connected = await RokuECPClient.shared.ensureConnected(to: device, primeState: true)
      if connected {
        Log.info("Remote", "✅ Connected to \(device.name) for state updates")

        // Force an immediate state snapshot so UI doesn't wait for the poll loop tick.
        await RokuECPClient.shared.snapshotActiveStateNow(for: device)
      }

      // Fetch apps for the device (if not cached)
      let hasApps = AppCacheManager.shared.hasApps(for: device.id)
      Log.debug("Remote", "📱 Device \(device.name) hasApps: \(hasApps)")
      if !hasApps {
        Log.debug("Remote", "📲 Fetching apps for \(device.name)...")
        await AppCacheManager.shared.fetchApps(for: device.id, deviceName: device.name)
      }
    } else {
      await RokuECPClient.shared.setMediaProgressEnabledDeviceIds([])
      await RokuECPClient.shared.setAppListRefreshEnabledDeviceIds([])
      await RokuECPClient.shared.setActiveStatePollingEnabledDeviceIds([])
      Log.warn("Remote", "Device not found for IP: \(ip)")
    }
  }

  // MARK: - Active State Polling Enablement

  private func updateActiveStatePollingEnablement(
    phase: ScenePhase? = nil,
    selectedDeviceId: String? = nil
  ) async {
    let effectivePhase = phase ?? scenePhase
    let effectiveDeviceId = selectedDeviceId ?? selection.selectedDeviceId

    let shouldEnable = RemoteControlPlatform.shouldEnableActiveStatePolling(
      scenePhase: effectivePhase,
      selectedDeviceId: effectiveDeviceId
    )
    await RokuECPClient.shared.setActiveStatePollingEnabledDeviceIds(
      shouldEnable ? Set([effectiveDeviceId].compactMap { $0 }) : []
    )
  }

  // MARK: - App Launch

  private func launchApp(_ app: RokuApp) {
    guard let tvId = PairingStore.shared.currentTVId else { return }
    guard let targetDevice = selection.selectedDevice else { return }

    // Required devices for wake-gated app launches:
    // - Always include the TV.
    // - Include the paired streamer (if present) so the "pair" wakes as a unit.
    var requiredDevices: [DeviceInfo] = []
    if let tv = discovery.tvs.first(where: { $0.id == tvId }) {
      requiredDevices.append(tv)
    }
    if let streamerId = PairingStore.shared.streamerIdForTV(tvId),
       let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId }) {
      requiredDevices.append(streamer)
    }

    Task {
      let success = await RokuECPClient.shared.launchAppInSilo(
        appId: app.id,
        siloId: tvId,
        requiredDevices: requiredDevices,
        targetDevice: targetDevice
      )
      if !success {
        Log.warn("Remote", "Failed to launch \(app.name)")
      }
    }
  }
}
