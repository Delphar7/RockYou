import SwiftUI

/// Portrait (compact) renderer for iPhone portrait and "narrow" layouts.
///
/// Goals (per spec):
/// - Explicit top/middle/bottom budgeting (no indirect coupling via insets).
/// - Top row anchored; its buttons feel like "the same scale" as the main controls.
/// - Bottom ticker (app strip) anchored; 2→1 lane pop with **no height jump**.
/// - App icons clamp at a configurable minimum scale; below that, icons stop shrinking.
@MainActor
struct RemotePortraitCompactLayoutView: View {
  let containerSize: CGSize
  /// When false, this view only renders the top+controls region. Intended for `.landscapeSplit`
  /// where the bottom ticker must span both panes (owned by `RemoteControlView`).
  var renderBottomTicker: Bool = true
  let selectedTVName: String?
  let selectedStreamerName: String?
  let selectedDeviceId: String?
  let hardwareControlsAvailable: Bool
  @Binding var showingConfigure: Bool
  @Binding var showingTVSelector: Bool
  let isKeyboardShown: Bool
  let onKeyboard: () -> Void
  let phonePowerDelay: TimeInterval?
  let phoneHomeDelay: TimeInterval?
  let appLaunchDelay: TimeInterval?
  let onAction: (RemoteAction) -> Void
  let onLaunchApp: (RokuApp) -> Void

  // MARK: - Natural size measurements (@ scale = 1.0)

  @State private var topBarNaturalHeight: CGFloat = 0
  @State private var controlClusterNaturalSize: CGSize = .zero
  @State private var progressHeaderNaturalHeight: CGFloat = 0

  private struct TopBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      let next = nextValue()
      if next > 0 { value = max(value, next) }
    }
  }

  private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      let next = nextValue()
      if next > 0 { value = max(value, next) }
    }
  }

  private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
      let next = nextValue()
      if next != .zero { value = next }
    }
  }

  private var baseIconSize: (width: CGFloat, height: CGFloat) {
    let config = AppStripConfig.config(for: .portraitCompact)
    let sizing = config.sizing ?? AppStripSizing.defaultSizing()
    switch sizing {
    case .fixed(let w, let h):
      if let w, let h {
        return (w, h)
      } else if let w {
        return (w, w * 0.75)
      } else if let h {
        return (h * (4.0 / 3.0), h)
      } else {
        let d = AppStripPlatformPolicy.defaultFixedIconSize
        return (d.width, d.height)
      }
    case .percent:
      // Percent sizing is relative to screen; for budgeting we need a stable baseline.
      let d = AppStripPlatformPolicy.defaultFixedIconSize
      return (d.width, d.height)
    }
  }

  // MARK: - Layout knobs

  /// Minimum icon scale relative to the selected base icon size (configurable constant).
  /// Note: AppStripView also has an internal "collapse to one lane" threshold; we honor the max.
  private var configuredMinIconScale: CGFloat { 2.0 / 3.0 }

  /// Match AppStripView's default lane spacing (points).
  private var stripLaneSpacing: CGFloat { 8 }

  /// Match AppStripView's fixed "strip extra" padding term (points).
  private var stripExtra: CGFloat { 8 }

  /// Small buffer between progress header and strip (points).
  private var progressToStripPadding: CGFloat { 2 }

  /// Small gap between top bar and the first row of controls (points).
  private var topToControlsPadding: CGFloat { RemoteCoreButtonMetrics.topKeyHeight * 0.4 }

  /// Cap for "extra horizontal breathing room" applied as additional spacing in non-DPad rows.
  private var maxSpacingBoost: CGFloat { 1.2 }

  private var measurementsReady: Bool {
    topBarNaturalHeight > 0 && controlClusterNaturalSize != .zero && progressHeaderNaturalHeight > 0
  }

  private struct Metrics: Sendable {
    let scale: CGFloat
    let bottomTickerHeight: CGFloat
    let bottomScale: CGFloat
    let lanes: Int
    let iconHeight: CGFloat
    let spacingBoost: CGFloat
  }

  private func solveMetrics() -> Metrics {
    let baseIconH = baseIconSize.height

    // Ensure we never ask AppStripView for 2 lanes at an icon height below its internal threshold,
    // otherwise it will silently collapse to 1 lane and cause a height jump.
    let minScaleFromStripPolicy: CGFloat =
      (baseIconH > 0) ? (AppStripPlatformPolicy.minIconHeightForMultiLane / baseIconH) : 1
    let minIconScale: CGFloat = max(configuredMinIconScale, minScaleFromStripPolicy)

    func bottomTickerHeight(forScale s: CGFloat) -> (height: CGFloat, bottomScale: CGFloat) {
      guard renderBottomTicker else { return (0, s) }
      let bottomScale = max(s, minIconScale)

      // Keep the region height stable across 2→1 lane pop:
      // - We budget assuming the 2-lane geometry at `bottomScale`.
      // - When we render 1 lane, we increase icon height to fill this same budget.
      let iconH2 = baseIconH * bottomScale
      let stripHeight2 = iconH2 * 2 + stripLaneSpacing + stripExtra
      let progressHeight = progressHeaderNaturalHeight * bottomScale
      let total = progressHeight + progressToStripPadding + stripHeight2
      return (total, bottomScale)
    }

    func fits(scale s: CGFloat) -> Bool {
      let topH = topBarNaturalHeight * s
      let controlsH = controlClusterNaturalSize.height * s
      let (bottomH, _) = bottomTickerHeight(forScale: s)
      let totalH = topH + topToControlsPadding * s + controlsH + bottomH

      let controlsW = controlClusterNaturalSize.width * s
      return totalH <= containerSize.height && controlsW <= containerSize.width
    }

    // Binary search for the maximum scale that fits.
    var lo: CGFloat = 0.20
    var hi: CGFloat = 1.00
    for _ in 0..<20 {
      let mid = (lo + hi) / 2
      if fits(scale: mid) { lo = mid } else { hi = mid }
    }
    let scale = max(0.01, min(1.0, lo))

    let (bottomH, bottomScale) = bottomTickerHeight(forScale: scale)

    // Decide lanes based on the "min icon scale" boundary.
    let lanes: Int = (scale >= minIconScale) ? 2 : 1

    // Set icon height so AppStripView's computed strip height stays constant across lane pop.
    let iconHeight: CGFloat
    if lanes == 2 {
      iconHeight = baseIconH * scale
    } else {
      // stripHeight2 = iconH2 * 2 + laneSpacing + extra
      // stripHeight1 = iconH1 * 1 + extra  => iconH1 = stripHeight2 - extra
      let iconH2 = baseIconH * bottomScale
      let stripHeight2 = iconH2 * 2 + stripLaneSpacing + stripExtra
      iconHeight = max(1, stripHeight2 - stripExtra)
    }

    // Width headroom → allow up to +20% spacing expansion in non-DPad rows.
    let controlsW = controlClusterNaturalSize.width * scale
    let headroom = (controlsW > 0) ? (containerSize.width / controlsW) : 1.0
    let spacingBoost = min(maxSpacingBoost, max(1.0, headroom * 0.9))

    return Metrics(
      scale: scale,
      bottomTickerHeight: bottomH,
      bottomScale: bottomScale,
      lanes: lanes,
      iconHeight: iconHeight,
      spacingBoost: spacingBoost
    )
  }

  private func resolvedMetrics() -> Metrics {
    if measurementsReady {
      return solveMetrics()
    }
    // Avoid referencing `RemoteControlPlatform` here: this view is compiled for multiple SDKs,
    // and platform-split policy is selected by build settings. A stable fallback is sufficient.
    let s: CGFloat = 0.98
    return Metrics(
      scale: s,
      bottomTickerHeight: CGFloat(0),
      bottomScale: s,
      lanes: 2,
      iconHeight: baseIconSize.height * s,
      spacingBoost: 1.0
    )
  }

  var body: some View {
    let metrics = resolvedMetrics()

    VStack(spacing: 0) {
      let topBarBaseline =
        RemoteTopBarView(
          scaleFactor: 1.0,
          selectedTVName: selectedTVName,
          selectedStreamerName: selectedStreamerName,
          selectedDeviceId: selectedDeviceId,
          hardwareControlsAvailable: hardwareControlsAvailable,
          showingTVSelector: $showingTVSelector,
          isKeyboardShown: isKeyboardShown,
          onKeyboard: onKeyboard,
          phonePowerDelay: phonePowerDelay,
          onAction: onAction
        )

      RemoteTopBarView(
        scaleFactor: metrics.scale,
        selectedTVName: selectedTVName,
        selectedStreamerName: selectedStreamerName,
        selectedDeviceId: selectedDeviceId,
        hardwareControlsAvailable: hardwareControlsAvailable,
        showingTVSelector: $showingTVSelector,
        isKeyboardShown: isKeyboardShown,
        onKeyboard: onKeyboard,
        phonePowerDelay: phonePowerDelay,
        onAction: onAction
      )
      // Measure the "natural" height at scale=1.0 to avoid feedback loops.
      .background(
        topBarBaseline
          .background(
            GeometryReader { proxy in
              Color.clear.preference(key: TopBarHeightPreferenceKey.self, value: proxy.size.height)
            }
          )
          .hidden()
      )
      .onPreferenceChange(TopBarHeightPreferenceKey.self) { h in
        if h > 0, h != topBarNaturalHeight { topBarNaturalHeight = h }
      }

      Spacer().frame(height: topToControlsPadding * metrics.scale)

      GeometryReader { _ in
        controlCluster(scaleFactor: metrics.scale, spacingBoost: metrics.spacingBoost)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .background(
        // Natural-size probe (scale=1, spacingBoost=1) – does not affect layout.
        controlCluster(scaleFactor: 1.0, spacingBoost: 1.0)
          .background(
            GeometryReader { proxy in
              Color.clear.preference(key: SizePreferenceKey.self, value: proxy.size)
            }
          )
          .hidden()
      )
      .onPreferenceChange(SizePreferenceKey.self) { s in
        if s != .zero, s != controlClusterNaturalSize { controlClusterNaturalSize = s }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if renderBottomTicker {
        bottomTicker(
          scale: metrics.scale,
          bottomScale: metrics.bottomScale,
          tickerHeight: metrics.bottomTickerHeight,
          lanes: metrics.lanes,
          iconHeight: metrics.iconHeight
        )
      }
    }
    .background(progressHeaderProbe.hidden())
  }

  // MARK: - Bottom ticker

  @ViewBuilder
  private func bottomTicker(
    scale: CGFloat,
    bottomScale: CGFloat,
    tickerHeight: CGFloat,
    lanes: Int,
    iconHeight: CGFloat
  ) -> some View {
    let _ = scale
    if let deviceId = selectedDeviceId {
      let config = AppStripConfig.config(for: .portraitCompact)
      VStack(spacing: 0) {
        // Always-reserved progress/time region:
        // - Scales down with the strip (clamped at the same boundary).
        NowPlayingProgressHeaderView(deviceId: deviceId)
          // Important: avoid `scaleEffect` + a smaller frame on an intrinsically-sized view,
          // which can clip. Give it a fixed unscaled layout height, then scale and re-frame.
          .frame(height: progressHeaderNaturalHeight)
          .scaleEffect(bottomScale, anchor: .top)
          .frame(height: progressHeaderNaturalHeight * bottomScale, alignment: .top)
          .padding(.bottom, progressToStripPadding)

        AppStripView(
          deviceId: deviceId,
          direction: config.direction,
          lanes: lanes,
          sizing: .fixed(height: iconHeight),
          showLabels: config.showLabels,
          appLaunchDelay: appLaunchDelay,
          onLaunch: onLaunchApp
        )
        .padding(config.padding)
      }
      .frame(height: tickerHeight)
    } else {
      EmptyView()
    }
  }

  private var progressHeaderProbe: some View {
    // Measure the max of:
    // - placeholder header (00:00)
    // - LIVE badge header
    // so the reserved height never clips when switching between modes.
    let liveState: DeviceState = {
      var s = DeviceState()
      s.isLive = true
      s.isLiveBlocked = false
      return s
    }()

    return ZStack {
      NowPlayingProgressView(state: DeviceState(), style: .compactHeader)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(key: HeightPreferenceKey.self, value: proxy.size.height)
          }
        )
        .hidden()

      NowPlayingProgressView(state: liveState, style: .compactHeader)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(key: HeightPreferenceKey.self, value: proxy.size.height)
          }
        )
        .hidden()
    }
    .onPreferenceChange(HeightPreferenceKey.self) { h in
      if h > 0, h != progressHeaderNaturalHeight { progressHeaderNaturalHeight = h }
    }
  }

  // MARK: - Controls cluster

  private func controlCluster(scaleFactor: CGFloat, spacingBoost: CGFloat) -> some View {
    VStack(spacing: 0) {
      RemoteNavRowSpacingBoostView(
        scaleFactor: scaleFactor,
        spacingBoost: spacingBoost,
        phoneHomeDelay: phoneHomeDelay,
        showingConfigure: $showingConfigure,
        onAction: onAction
      ).padding(.bottom, 6 * scaleFactor)

      RemoteDPadClusterView(
        scaleFactor: scaleFactor,
        onAction: onAction,
        topRowToDPadSpacing: 6
      )
      .padding(.bottom, 10 * scaleFactor)

      RemoteTransportControlsSpacingBoostView(
        scaleFactor: scaleFactor,
        spacingBoost: spacingBoost,
        onAction: onAction
      )
      .padding(.bottom, 8 * scaleFactor)

      RemoteVolumeControlsSpacingBoostView(
        scaleFactor: scaleFactor,
        spacingBoost: spacingBoost,
        hardwareControlsAvailable: hardwareControlsAvailable,
        onAction: onAction
      ).padding(.bottom, 10 * scaleFactor)
    }
  }
}

// MARK: - Row variants (spacing boost)

private struct RemoteNavRowSpacingBoostView: View {
  let scaleFactor: CGFloat
  let spacingBoost: CGFloat
  let phoneHomeDelay: TimeInterval?
  @Binding var showingConfigure: Bool
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor * spacingBoost) {
      TopKeyButton(
        systemName: "chevron.left",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.back) }

      if let phoneHomeDelay, phoneHomeDelay > 0 {
        TopKeyButton(
          systemName: "house.fill",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
        ) {}
        .sweepable(
          icon: "house.fill",
          color: .indigo,
          delay: phoneHomeDelay,
          tooltip: "Hold to go home",
          onSweepComplete: { onAction(.home) }
        )
      } else {
        TopKeyButton(
          systemName: "house.fill",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
        ) { onAction(.home) }
      }

      TopKeyButton(
        systemName: "gearshape.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { showingConfigure = true }
    }
  }
}

private struct RemoteTransportControlsSpacingBoostView: View {
  let scaleFactor: CGFloat
  let spacingBoost: CGFloat
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: RemoteCoreButtonMetrics.circleKeyHorizontalSpacing * scaleFactor * spacingBoost) {
      CircleKeyButton(
        systemName: "backward.fill",
        size: RemoteCoreButtonMetrics.circleKeySize * scaleFactor,
        baseColor: rokuDarkPurple
      ) { onAction(.rewind) }
      CircleKeyButton(
        systemName: "playpause.fill",
        size: RemoteCoreButtonMetrics.circleKeyLargeSize * scaleFactor,
        baseColor: rokuDarkPurple
      ) { onAction(.playPause) }
      CircleKeyButton(
        systemName: "forward.fill",
        size: RemoteCoreButtonMetrics.circleKeySize * scaleFactor,
        baseColor: rokuDarkPurple
      ) { onAction(.forward) }
    }
    .padding(.top, RemoteCoreButtonMetrics.circleKeyVerticalPadding * scaleFactor)
  }
}

private struct RemoteVolumeControlsSpacingBoostView: View {
  let scaleFactor: CGFloat
  let spacingBoost: CGFloat
  let hardwareControlsAvailable: Bool
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor * spacingBoost) {
      TopKeyButton(
        systemName: "speaker.slash.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.volumeMute) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      TopKeyButton(
        systemName: "speaker.minus.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.volumeDown) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      TopKeyButton(
        systemName: "speaker.plus.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.volumeUp) }
      .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
    }
    .padding(.vertical, RemoteCoreButtonMetrics.topKeyVerticalPadding * scaleFactor)
  }
}
