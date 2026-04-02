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
  @State private var headerScaleFactorOverride: CGFloat? = nil
  @State private var appStripScaleFactorOverride: CGFloat? = nil
  @State private var lastControlsFitScale: CGFloat? = nil
  @State private var controlsNaturalSize: CGSize = .zero
  @State private var horizontalStripLanesOverride: Int? = nil

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

  /// Scale factor used by the top bar. When the controls compute a tighter fit scale, we adopt it
  /// so the keyboard/power buttons consume the same real estate as the main remote.
  private var headerScaleFactor: CGFloat { headerScaleFactorOverride ?? scaleFactor }

  // MARK: - Controls scale reporting (to avoid keyboard/power buttons drifting from main controls)

  struct ControlsScalePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
      // Prefer the most recent non-nil value.
      if let next = nextValue() { value = next }
    }
  }

  struct ControlsNaturalSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
      let next = nextValue()
      if next != .zero { value = next }
    }
  }

  /// Tweakable policy knobs for "cluster tappability" vs "AppStrip richness" tradeoffs.
  private enum AppStripLanePolicy {
    /// Minimum acceptable cluster scale before we force the horizontal AppStrip into 1 lane.
    static var minClusterScale: CGFloat { RemoteControlPlatform.minClusterScaleForStripLanePolicy }
    /// Hysteresis to avoid flapping 2↔1 during macOS window resizing.
    static var clusterScaleHysteresis: CGFloat {
      RemoteControlPlatform.clusterScaleHysteresisForStripLanePolicy
    }
    /// Minimum usable AppStrip icon height (below this, strip is effectively unusable).
    static var minStripIconHeight: CGFloat { RemoteControlPlatform.minStripIconHeightForLanePolicy }
    /// Match `AppStripView` default lane spacing.
    static var stripLaneSpacing: CGFloat = 8
    /// Match `AppStripView` "strip extra" constant.
    static var stripExtra: CGFloat = 8
  }

  var body: some View {
    GeometryReader { geometry in
      let textEditStatus = RokuTextEditStateManager.shared.status(for: selection.selectedDeviceId)
      ZStack(alignment: .top)  {
        shellLayout(in: geometry)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Sweep overlays (tooltip + sweep animation)
        TooltipOverlayView()
        SweepOverlayView()
      }
      .onPreferenceChange(ControlsScalePreferenceKey.self) { newValue in
        guard let newValue else { return }
        // Avoid feedback/render cycles: only update when the scale changes meaningfully.
        let clamped = max(0.10, min(1.0, newValue))
        lastControlsFitScale = clamped
        let old = headerScaleFactorOverride ?? scaleFactor
        if abs(clamped - old) >= 0.02 {
          headerScaleFactorOverride = clamped
        }
        // AppStrip should track the controls fit-scale (bidirectionally with hysteresis).
        // This ensures icons grow back when the window expands, avoiding a ratchet effect.
        let prev = appStripScaleFactorOverride ?? 1.0
        if abs(clamped - prev) >= 0.02 {
          appStripScaleFactorOverride = clamped
        }

        recomputeHorizontalStripPolicy()
      }
      .onPreferenceChange(ControlsNaturalSizePreferenceKey.self) { s in
        if s != .zero, s != controlsNaturalSize {
          controlsNaturalSize = s
          recomputeHorizontalStripPolicy()
        }
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
          Log.debug(
            "Keyboard", "User dismissed keyboard while textedit active (suppressing auto-present)")
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
        if newValue == .active {
          Task { await reconnectOnResume() }
        }
      }
      .onChange(of: selection.selectedDeviceId) { _, newDeviceId in
        Task { await updateActiveStatePollingEnablement(selectedDeviceId: newDeviceId) }
      }
      .onChange(of: geometry.size) { _, newSize in
        // Platform-specific: iOS freezes containerSize while keyboard is active to prevent jitter.
        if RemoteControlPlatform.freezesContainerSizeDuringKeyboard && showingKeyboard { return }
        containerSize = newSize
        recomputeHorizontalStripPolicy()
      }
      .onChange(of: layoutMode) { oldMode, newMode in
        // Reset one-shot scale overrides when the overall layout mode changes
        // (e.g. rotation or major size class transitions).
        if oldMode != newMode {
          appStripScaleFactorOverride = nil
          lastControlsFitScale = nil
          controlsNaturalSize = .zero
          horizontalStripLanesOverride = nil
        }
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
    .platformKeyboardSheet(isPresented: $showingKeyboard, target: keyboardTarget)
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
          let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId })
        {
          required.append(streamer)
        }
        return KeyboardTarget(siloId: tvId, requiredDevices: required, targetDevice: target)
      case .streamer(let streamerId):
        guard let device = discovery.streamingDevices.first(where: { $0.id == streamerId }) else {
          return nil
        }
        return KeyboardTarget(siloId: streamerId, requiredDevices: [device], targetDevice: device)
      }
    }

    // Legacy fallback: selected TV id
    guard let tvId = pairingStore.currentTVId else { return nil }
    guard let target = self.selection.selectedDevice else { return nil }
    var required: [DeviceInfo] = []
    if let tv = discovery.tvs.first(where: { $0.id == tvId }) { required.append(tv) }
    if let streamerId = pairingStore.streamerIdForTV(tvId),
      let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId })
    {
      required.append(streamer)
    }
    return KeyboardTarget(siloId: tvId, requiredDevices: required, targetDevice: target)
  }

  // MARK: - New slot-based shell renderer

  @ViewBuilder
  private func shellLayout(in geometry: GeometryProxy) -> some View {
    let stripConfig = AppStripConfig.config(for: layoutMode)

    if stripConfig.isVisible, stripConfig.direction == .vertical {
      // Vertical strip must span the full height (header has lower "ownership precedence").
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          headerBar()
          shellContent(in: geometry)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        shellAppStrip(direction: .vertical)
      }
    } else {
      if RemoteControlPlatform.usesScrollableShellForKeyboard {
        // Uses ZStack with header overlay + ScrollView for keyboard support.
        // This eliminates all geometry transitions when keyboard opens/closes.
        ZStack(alignment: .top) {
          shellScrollableContent(in: geometry, stripConfig: stripConfig)
          headerBar()
        }
      } else {
        VStack(spacing: 0) {
          headerBar()
          shellScrollableContent(in: geometry, stripConfig: stripConfig)
        }
      }
    }
  }

  /// The content area. On iOS, ALWAYS wrapped in a ScrollView for consistent layout.
  /// Always includes an invisible header spacer so the real header (on top via ZStack) aligns correctly.
  @ViewBuilder
  private func shellScrollableContent(
    in geometry: GeometryProxy,
    stripConfig: AppStripConfig
  ) -> some View {
    let contentStack = VStack(spacing: 0) {
      // Invisible header spacer - the real header is overlaid on top via ZStack.
      if RemoteControlPlatform.usesScrollableShellForKeyboard {
        headerBar()
          .opacity(0)
      }

      shellContent(in: geometry)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()

      if layoutMode == .portraitCompact, let deviceId = selection.selectedDeviceId  {
        NowPlayingProgressHeaderView(deviceId: deviceId)
          .padding(.top, 8)
          .padding(.bottom, 2)
      }

      if stripConfig.isVisible {
        shellAppStrip(direction: .horizontal)
          .layoutPriority(1)
      }
    }

    // Platform-specific: iOS wraps in ScrollView for keyboard support; macOS uses bare stack.
    contentStack.platformKeyboardScrollWrapper(
      containerSize: containerSize,
      showingKeyboard: showingKeyboard,
      target: keyboardTarget(),
      onDismiss: { showingKeyboard = false }
    )
  }

  private func headerBar() -> some View {
    RemoteTopBarView(
      scaleFactor: headerScaleFactor,
      selectedTVName: selection.selectedTVName,
      selectedStreamerName: selection.selectedStreamerName,
      selectedDeviceId: selection.selectedDeviceId,
      hardwareControlsAvailable: selection.hardwareControlsAvailable,
      showingTVSelector: $showingTVSelector,
      isKeyboardShown: showingKeyboard,
      onKeyboard: keyboardTapped,
      phonePowerDelay: settings.phonePowerDelay,
      onAction: onAction,
      layoutMode: layoutMode,
      keyboardTarget: keyboardTarget()
    )
    .padding(.top, 6)
    .padding(.bottom, 6)
    .background {
      // When keyboard is up, content scrolls behind the header - use blur material.
      // Otherwise, a simple dark background suffices.
      if showingKeyboard && RemoteControlPlatform.usesScrollableShellForKeyboard {
        Rectangle()
          .fill(Color.black.opacity(AppOpacity.nearlyOpaque))
          .blur(radius: 12)
          .environment(\.colorScheme, .dark)
          .padding(.top, -100)  // Extend upward so blur doesn't fade at top edge
          .ignoresSafeArea(.all, edges: .top)
          .contentShape(Rectangle())
          .sweepBlockingZone()  // Block sweepable gestures from bleeding through
      } else {
        Color.black.opacity(AppOpacity.standard)
      }
    }
  }

  @ViewBuilder
  private func shellContent(in geometry: GeometryProxy) -> some View {
    switch layoutMode {
    case .portraitCompact:
      ZStack {
        FullScreenDomeView()
        GeometryReader { proxy in
          RemotePortraitCompactControlsView(
            containerSize: proxy.size,
            selectedDeviceId: selection.selectedDeviceId,
            hardwareControlsAvailable: selection.hardwareControlsAvailable,
            showingConfigure: $showingConfigure,
            phoneHomeDelay: settings.phoneHomeDelay,
            onAction: onAction
          )
        }
        DomeTapThroughOverlay()
      }
      // Ensure a stable "breathing gap" between header and the top purple row.
      .padding(.top, 12)

    case .landscapeSplit:
      HStack(spacing: 0) {
        ZStack {
          FullScreenDomeView()
          GeometryReader { proxy in
            // Reduce usable height by bottom clearance so button shadows don't clip into AppStrip.
            let clearance: CGFloat = 16
            let adjustedSize = CGSize(width: proxy.size.width, height: proxy.size.height - clearance)
            RemotePortraitCompactControlsView(
              containerSize: adjustedSize,
              selectedDeviceId: selection.selectedDeviceId,
              hardwareControlsAvailable: selection.hardwareControlsAvailable,
              showingConfigure: $showingConfigure,
              phoneHomeDelay: settings.phoneHomeDelay,
              onAction: onAction
            )
            // Ensure a stable "breathing gap" between header and the top purple row.
            .padding(.top, 12)
          }
          DomeTapThroughOverlay()
        }
        .frame(maxWidth: .infinity)

        Divider()
          .background(Color.white.opacity(0.1))

        // Info pane: Scroll vertically if content exceeds available height.
        // This prevents the info pane from forcing the layout taller and pushing
        // the AppStrip off-screen when window height is reduced.
        ScrollView(.vertical, showsIndicators: false)  {
          NowPlayingPanel(deviceId: selection.selectedDeviceId)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
      }

    case .landscapeCompact:
      LandscapeRemoteControlsView(
        onAction: onAction,
        showingConfigure: $showingConfigure,
        hardwareControlsAvailable: selection.hardwareControlsAvailable
      )

    case .portraitExpanded:
      GeometryReader { proxy in
        let h = proxy.size.height
        HStack(spacing: 0) {
          VStack(spacing: 0) {
            InfoTopPanel(deviceId: selection.selectedDeviceId)
              .frame(height: h / 3)
              .padding(16)

            Divider()
              .background(Color.white.opacity(AppOpacity.subtle))

            LandscapeRemoteControlsView(
              onAction: onAction,
              showingConfigure: $showingConfigure,
              hardwareControlsAvailable: selection.hardwareControlsAvailable
            )
            .frame(height: h / 3)

            Divider()
              .background(Color.white.opacity(AppOpacity.subtle))
              .padding(.bottom, 16)

            InfoBottomPanel(deviceId: selection.selectedDeviceId)
              .frame(height: h / 3)
              .padding(16)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }

  @ViewBuilder
  private func shellAppStrip(direction: AppStripDirection) -> some View {
    if let deviceId = selection.selectedDeviceId {
      let config = AppStripConfig.config(for: layoutMode)
      if config.isVisible {
        let lanes =
          RemoteControlPlatform.appStripLanesOverride(layoutMode: layoutMode, direction: direction)
          ?? config.lanes

        let stripScale =
          RemoteControlPlatform.appStripScaleFactor(
            containerSize: containerSize, layoutMode: layoutMode)
        // AppStrip should track the controls fit-scale, but shrink a bit less aggressively.
        // Apply a +25% modifier and clamp to never exceed the base size.
        let controlsScale = min(1.0, (appStripScaleFactorOverride ?? 1.0) * 1.25)
        let baseSizing = (config.sizing ?? .fixed()).scaled(by: stripScale)
        let scaledSizing = baseSizing.scaled(by: controlsScale)

        let effectiveLanes: Int = {
          guard direction == .horizontal else { return lanes }
          return horizontalStripLanesOverride ?? lanes
        }()
        // Always use scaled sizing for icons; the lane-policy logic is only about 1-vs-2 lanes,
        // not a fixed icon height that bypasses normal scaling.
        let effectiveSizing: AppStripSizing = scaledSizing

        let horizontalInset = RemoteControlPlatform.appStripHorizontalInset(layoutMode: layoutMode)

        AppStripView(
          deviceId: deviceId,
          direction: direction,
          lanes: effectiveLanes,
          sizing: effectiveSizing,
          showLabels: config.showLabels,
          appLaunchDelay: settings.phoneAppLaunchDelay,
          onLaunch: { app in launchApp(app) }
        )
        .frame(maxHeight: direction == .vertical ? .infinity : nil)
        .padding(config.padding)
        .padding(.horizontal, horizontalInset)
        .safeAreaPadding(
          .bottom, RemoteControlPlatform.appStripSafeAreaBottomPadding(direction: direction))
      }
    }
  }

  /// Height-domain policy: keep the cluster above `minClusterScale` by forcing the horizontal
  /// AppStrip into 1 lane. Icon sizing is handled by `appStripScaleFactorOverride` (same as landscapeSplit).
  private func recomputeHorizontalStripPolicy() {
    guard layoutMode == .portraitCompact else {
      horizontalStripLanesOverride = nil
      return
    }
    guard let scaleNow = lastControlsFitScale else { return }

    let config = AppStripConfig.config(for: layoutMode)
    guard config.isVisible, config.direction == .horizontal else { return }
    guard config.lanes > 1 else { return }

    let minCluster = AppStripLanePolicy.minClusterScale
    let hysteresis = AppStripLanePolicy.clusterScaleHysteresis

    let lanesNow = horizontalStripLanesOverride ?? config.lanes

    if lanesNow > 1 {
      // Force 1 lane if the cluster is below the fat-finger threshold.
      if scaleNow < minCluster {
        horizontalStripLanesOverride =  1
      }
    } else {
      // Consider switching back to 2 lanes using hysteresis.
      if scaleNow >= (minCluster + hysteresis) {
        horizontalStripLanesOverride = nil
      }
    }
  }

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
      DeviceStateManager.shared.setConnecting(true, for: device.id)
      defer { DeviceStateManager.shared.setConnecting(false, for: device.id) }

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

  // MARK: - Resume Reconnection

  /// Called when the app returns to foreground. Tears down any stale WebSocket and
  /// reconnects fresh, then resets gesture routers that may have been mid-flight.
  /// Key presses are discarded while the reconnecting flag is set (see `sendActionInSilo`).
  private func reconnectOnResume() async {
    #if os(iOS)
      SweepableTouchRouter.resetAllOnResume()
    #endif

    guard let device = selection.selectedDevice else { return }

    DeviceStateManager.shared.setConnecting(true, for: device.id)
    defer { DeviceStateManager.shared.setConnecting(false, for: device.id) }

    await RokuECPClient.shared.tearDownAndBeginReconnect(for: device.ipAddress)
    await RokuECPClient.shared.ensureConnected(to: device, primeState: true)
    await RokuECPClient.shared.clearReconnecting(for: device.ipAddress)
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
      let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId })
    {
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
