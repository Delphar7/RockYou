import SwiftUI

/// Controls-only portrait compact renderer.
///
/// The surface portion for portrait compact layouts:
/// - NO top bar ownership (header is owned by the shell)
/// - NO app strip ownership (global strip is owned by the shell)
@MainActor
struct RemotePortraitCompactControlsView: View {
  let containerSize: CGSize
  let selectedDeviceId: String?
  let hardwareControlsAvailable: Bool
  @Binding var showingConfigure: Bool
  let phoneHomeDelay: TimeInterval?
  let onAction: (RemoteAction) -> Void

  // MARK: - Natural size measurements (@ scale = 1.0)

  @State private var controlClusterNaturalSize: CGSize = .zero

  private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
      let next = nextValue()
      if next != .zero { value = next }
    }
  }

  // MARK: - Layout knobs

  /// Cap for "extra horizontal breathing room" applied as additional spacing in non-DPad rows.
  private var maxSpacingBoost: CGFloat { 1.2 }

  private var measurementsReady: Bool {
    controlClusterNaturalSize != .zero
  }

  private struct Metrics: Sendable {
    let scale: CGFloat
    let spacingBoost: CGFloat
  }

  private func solveMetrics() -> Metrics {
    func fits(scale s: CGFloat) -> Bool {
      let controlsH = controlClusterNaturalSize.height * s
      let totalH = controlsH

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

    // Width headroom → allow up to +20% spacing expansion in non-DPad rows.
    let controlsW = controlClusterNaturalSize.width * scale
    let headroom = (controlsW > 0) ? (containerSize.width / controlsW) : 1.0
    let spacingBoost = min(maxSpacingBoost, max(1.0, headroom * 0.9))

    return Metrics(scale: scale, spacingBoost: spacingBoost)
  }

  private func resolvedMetrics() -> Metrics {
    if measurementsReady {
      return solveMetrics()
    }
    // Stable fallback while probes measure natural sizes.
    return Metrics(scale: 0.98, spacingBoost: 1.0)
  }

  var body: some View {
    let metrics = resolvedMetrics()
    VStack(spacing: 0) {
      GeometryReader { _ in
        controlCluster(scaleFactor: metrics.scale, spacingBoost: metrics.spacingBoost)
          // Center the cluster vertically; excess space (from width-constrained scaling)
          // distributes above and below.
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
      .background(
        // Natural-size probe (scale=1, spacingBoost=1) – does not affect layout.
        // Uses forMeasurement=true to avoid RealityKit in hidden views (breaks Metal rendering).
        controlCluster(scaleFactor: 1.0, spacingBoost: 1.0, forMeasurement: true)
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
    // Report the chosen fit scale up to the shell so the header buttons can match.
    .preference(key: RemoteControlView.ControlsScalePreferenceKey.self, value: metrics.scale)
    // Also report the natural (unscaled) cluster size so the shell can make height-domain
    // AppStrip lane decisions (e.g. keep the cluster above a fat-finger threshold on SE3).
    .preference(
      key: RemoteControlView.ControlsNaturalSizePreferenceKey.self, value: controlClusterNaturalSize
    )
  }

  // MARK: - Controls cluster

  private func controlCluster(scaleFactor: CGFloat, spacingBoost: CGFloat, forMeasurement: Bool = false) -> some View {
    return VStack(spacing: 0) {
      RemoteNavRowSpacingBoostView(
        scaleFactor: scaleFactor,
        spacingBoost: spacingBoost,
        phoneHomeDelay: phoneHomeDelay,
        showingConfigure: $showingConfigure,
        onAction: onAction
      ).padding(.bottom, 20 * scaleFactor)

      RemoteDPadClusterView(
        scaleFactor: scaleFactor,
        onAction: onAction,
        topRowToDPadSpacing: 6,
        forMeasurement: forMeasurement
      )
      .padding(.bottom, 10 * scaleFactor)

      RemoteTransportControlsSpacingBoostView(
        scaleFactor: scaleFactor,
        spacingBoost: spacingBoost,
        onAction: onAction
      )
      .padding(.bottom, 18 * scaleFactor)

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
    HStack(
      spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor * spacingBoost
    ) {
      TopKeyButton(
        systemName: "chevron.left",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.back) }

      TopKeyButton(
        systemName: "house.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) {}
      .sweepable(
        icon: "house.fill",
        color: .indigo,
        delay: phoneHomeDelay ?? 0,
        tooltip: "Hold to go home",
        onSweepComplete: { onAction(.home) }
      )

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
    HStack(
      spacing: RemoteCoreButtonMetrics.circleKeyHorizontalSpacing * scaleFactor * spacingBoost
    ) {
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
    HStack(
      spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor * spacingBoost
    ) {
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
  }
}
