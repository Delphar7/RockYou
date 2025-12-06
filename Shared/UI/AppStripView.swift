//
//  AppStripView.swift
//  RockYou
//
//  Unified scrollable strip of app icons for quick launch.
//  Supports horizontal/vertical orientation and configurable lanes (rows/columns).
//

import SwiftUI

// MARK: - App Strip Configuration

enum AppStripDirection {
  case horizontal
  case vertical
}

enum AppStripSizing {
  /// Fixed size per icon - both optional, computed at 4:3 ratio if one missing
  case fixed(iconWidth: CGFloat?, iconHeight: CGFloat?)
  /// Percent of screen dimension (height for horizontal, width for vertical)
  case percent(CGFloat)

  // MARK: - Platform Default Sizing

  /// Get the default sizing for the current platform
  /// Centralized configuration to avoid duplication
  static func defaultSizing() -> AppStripSizing {
    AppStripPlatformPolicy.defaultSizing
  }

  // MARK: - Convenience Factory Methods

  /// Fixed size with width only (height computed at 4:3 ratio)
  static func fixed(width: CGFloat) -> AppStripSizing {
    .fixed(iconWidth: width, iconHeight: nil)
  }

  /// Fixed size with height only (width computed at 4:3 ratio)
  static func fixed(height: CGFloat) -> AppStripSizing {
    .fixed(iconWidth: nil, iconHeight: height)
  }

  /// Fixed size with both dimensions
  static func fixed(width: CGFloat, height: CGFloat) -> AppStripSizing {
    .fixed(iconWidth: width, iconHeight: height)
  }

  /// Fixed size with default platform sizing
  static func fixed() -> AppStripSizing {
    defaultSizing()
  }
}

// MARK: - App Strip View

struct AppStripView: View {
  let apps: [RokuApp]
  let deviceId: String
  let onLaunch: (RokuApp) -> Void

  var direction: AppStripDirection = .horizontal
  var lanes: Int = 1
  var sizing: AppStripSizing = AppStripSizing.defaultSizing()
  var showLabels: Bool = true
  /// Hold-to-launch delay for app icons. If nil, sweepable is disabled and icons tap-to-launch.
  var appLaunchDelay: TimeInterval? = 1.0
  var spacing: CGFloat = 8  // Spacing between items in scroll direction
  var laneSpacing: CGFloat? = nil  // Spacing between lanes (nil = same as spacing)

  @ObservedObject private var cache = AppCacheManager.shared
  @State private var isScrollGestureActive = false

  @Environment(\.glowAnimationForegroundEnabled) private var glowAnimationForegroundEnabled
  @Environment(\.glowAnimationLastUserInteractionAt) private var glowAnimationLastUserInteractionAt

  // Single-flight pulse state owned by the strip (NOT by individual icons).
  @State private var glowPulseFactor: CGFloat = GlowPulseConfig.baseOpacity
  @State private var lastPulseStartedAt: Date = .distantPast
  @State private var pulsePausedForInactivity: Bool = false
  @State private var pulseRestartNonce: Int = 0

  private var effectiveLaneSpacing: CGFloat { laneSpacing ?? spacing }

  private var haloVerticalPadding: (top: CGFloat, bottom: CGFloat) {
    AppStripPlatformPolicy.haloVerticalPadding(showLabels: showLabels, scrollAxis: scrollAxis)
  }

  var body: some View {
    // Reference iconVersion to trigger re-render when icons load
    let _ = cache.iconVersion
    // Reference mruVersion to trigger re-render when MRU changes (sorting)
    let _ = cache.mruVersion

    let sizes = calculateSizes()

    let activeAppId = DeviceStateManager.shared.states[deviceId]?.activeApp
    let _ = glowPulseFactor  // keep dependency explicit
    let pulseTaskId =
      "\(deviceId)|\(activeAppId ?? "")|\(glowAnimationForegroundEnabled ? "fg" : "bg")|\(pulseRestartNonce)"

    let base = Group {
      if apps.isEmpty {
        emptyView(sizes: sizes)
      } else {
        scrollableGrid(sizes: sizes)
      }
    }
    base
      .task(id: pulseTaskId) {
        guard AppStripPlatformPolicy.supportsGlowPulse else { return }

        // Reset when the task starts (must be MainActor for @State writes).
        await MainActor.run {
          glowPulseFactor = GlowPulseConfig.baseOpacity
          pulsePausedForInactivity = false
        }

        guard glowAnimationForegroundEnabled else { return }
        guard let activeAppId, !activeAppId.isEmpty else { return }

        // Used for inactivity gating: allow pulses for at least `inactivityTimeoutSeconds`
        // after becoming eligible, even if the user hasn't interacted yet.
        let taskBeganAt = Date()

        DebugBuild.run {
          Log.debug(
            "GlowPulse",
            "strip task start device=\(deviceId) activeApp=\(activeAppId) fg=\(glowAnimationForegroundEnabled) restart=\(pulseRestartNonce)"
          )
        }

        // Unconditional start delay (spec).
        try? await Task.sleep(
          nanoseconds: UInt64(GlowPulseConfig.startDelaySeconds * 1_000_000_000))
        guard !Task.isCancelled else { return }

        var pulseIndex = 0
        while !Task.isCancelled, glowAnimationForegroundEnabled {
          if AppStripPlatformPolicy.inactivityGatingEnabled {
            // Inactivity gating: pause only after *no gesture for N seconds*.
            let lastActivity = max(glowAnimationLastUserInteractionAt, taskBeganAt)
            if Date().timeIntervalSince(lastActivity) >= GlowPulseConfig.inactivityTimeoutSeconds {
              await MainActor.run {
                pulsePausedForInactivity = true
                glowPulseFactor = GlowPulseConfig.baseOpacity
              }
              DebugBuild.run {
                Log.debug(
                  "GlowPulse",
                  "strip paused for inactivity device=\(deviceId) activeApp=\(activeAppId) lastTouch=\(glowAnimationLastUserInteractionAt) taskStart=\(taskBeganAt)"
                )
              }
              return
            }
          }

          pulseIndex += 1
          await MainActor.run {
            lastPulseStartedAt = Date()
          }
          DebugBuild.run {
            Log.debug(
              "GlowPulse",
              "strip pulse \(pulseIndex) start device=\(deviceId) activeApp=\(activeAppId)"
            )
          }

          // One pulse: "lights" curve. Baseline → brighter → off → baseline.
          let steps = max(12, Int(GlowPulseConfig.waveSeconds * GlowPulseConfig.waveFPS))
          let dt = GlowPulseConfig.waveSeconds / Double(steps)
          let base = Double(GlowPulseConfig.baseOpacity)

          for step in 0...steps {
            guard !Task.isCancelled else { return }
            let t = Double(step) * dt
            let u = max(0.0, min(1.0, t / GlowPulseConfig.waveSeconds))  // 0..1
            let opacity = GlowPulseCurve.opacity(u: u, baseline: base)
            await MainActor.run {
              glowPulseFactor = CGFloat(max(0.0, min(1.0, opacity)))
            }
            if step != steps {
              try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
          }

          DebugBuild.run {
            // Temporary: log wave parameters once per pulse.
            let baseStr = String(format: "%.2f", Double(GlowPulseConfig.baseOpacity))
            let waveStr = String(format: "%.2f", GlowPulseConfig.waveSeconds)
            let periodStr = String(format: "%.2f", GlowPulseConfig.periodSeconds)
            Log.debug(
              "GlowPulse",
              "strip wave params device=\(deviceId) activeApp=\(activeAppId) base=\(baseStr) wave=\(waveStr)s fps=\(Int(GlowPulseConfig.waveFPS)) period=\(periodStr)s"
            )
          }

          // Snap back to baseline (avoid drift).
          await MainActor.run {
            glowPulseFactor = GlowPulseConfig.baseOpacity
          }

          DebugBuild.run {
            Log.debug(
              "GlowPulse",
              "strip pulse \(pulseIndex) end device=\(deviceId) activeApp=\(activeAppId)"
            )
          }

          // Idle until next wave start (start-to-start period).
          let idle = max(0, GlowPulseConfig.periodSeconds - GlowPulseConfig.waveSeconds)
          try? await Task.sleep(nanoseconds: UInt64(idle * 1_000_000_000))
        }
      }
      .onChange(of: glowAnimationLastUserInteractionAt) { _, newValue in
        guard AppStripPlatformPolicy.inactivityGatingEnabled else { return }
        guard glowAnimationForegroundEnabled else { return }
        guard pulsePausedForInactivity else { return }
        // Any new interaction re-arms the pulse loop.
        if newValue > lastPulseStartedAt {
          pulsePausedForInactivity = false
          pulseRestartNonce &+= 1
        }
      }
  }

  // MARK: - Grid Layout

  private func scrollableGrid(sizes: IconSizes) -> some View {
    // The glow halo on the active icon is intentionally allowed to extend beyond the icon bounds.
    // Scroll views/grid containers can clip at their edges, so give the content a small safe inset
    // so edge icons (top/left/right/bottom) don’t lose their halo.
    let haloSafePadding: CGFloat = AppStripPlatformPolicy.haloSafePaddingAlongScrollAxis

    let content = gridContent(sizes: sizes)
      .padding(direction == .horizontal ? .horizontal : .vertical, 4)
      // Only add padding along the scroll axis (left/right for horizontal strips).
      // Top/bottom padding changes the perceived layout too much.
      .padding(scrollAxis == .horizontal ? .horizontal : .vertical, haloSafePadding)
      // macOS: give the halo real vertical room (mac has layout headroom).
      .padding(.top, haloVerticalPadding.top)
      .padding(.bottom, haloVerticalPadding.bottom)

    return AnyView(
      AppStripScrollView(
        content: content,
        axis: scrollAxis,
        direction: direction,
        deviceId: deviceId,
        onScrollGestureChanged: { active in
          isScrollGestureActive = active
        }
      )
      .environment(\.sweepSuppressed, isScrollGestureActive)
      .frame(
        width: direction == .vertical ? sizes.stripSize : nil,
        height: direction == .horizontal ? (sizes.stripSize + platformExtraHeight) : nil
      )
    )
  }

  @ViewBuilder
  private func gridContent(sizes: IconSizes) -> some View {
    if direction == .horizontal {
      LazyHGrid(
        rows: Array(
          repeating: GridItem(.fixed(sizes.cellSize), spacing: effectiveLaneSpacing), count: lanes),
        spacing: spacing
      ) {
        appButtons(sizes: sizes)
      }
    } else {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.fixed(sizes.cellSize), spacing: effectiveLaneSpacing), count: lanes),
        spacing: spacing
      ) {
        appButtons(sizes: sizes)
      }
    }
  }

  private var scrollAxis: Axis.Set {
    direction == .horizontal ? .horizontal : .vertical
  }

  // MARK: - App Buttons

  @ViewBuilder
  private func appButtons(sizes: IconSizes) -> some View {
    // Slot-based strip:
    // - Geometry is stable: each frame is an index (0..n-1).
    // - The app shown in a slot can change if ordering changes.
    // - On press-began we snapshot "app at slot" so sweep icon + launch uses a consistent target.
    let slotCount = orderedAppsForDisplay().count
    let activeAppId = DeviceStateManager.shared.states[deviceId]?.activeApp
    let pulseFactor = AppStripPlatformPolicy.supportsGlowPulse ? glowPulseFactor : 1.0
    ForEach(0..<slotCount, id: \.self) { slotIndex in
      AppStripSlotButton(
        slotIndex: slotIndex,
        appsProvider: { orderedAppsForDisplay() },
        deviceId: deviceId,
        config: AppIconConfig(
          width: sizes.iconWidth,
          height: sizes.iconHeight,
          cornerRadius: sizes.cornerRadius,
          labelFont: sizes.labelFont,
          showLabel: showLabels,
          showShadow: platformShowShadow
        ),
        activeAppId: activeAppId,
        glowPulseFactor: pulseFactor,
        launchDelay: appLaunchDelay,
        onLaunch: onLaunch
      )
      .onAppear {
        // Prefetch visible + buffer (based on slot indices).
        let ordered = orderedAppsForDisplay()
        let visibleRange = max(0, slotIndex - 1)..<min(ordered.count, slotIndex + 2)
        cache.prefetchIcons(
          appIds: ordered.map(\.id),
          deviceId: deviceId,
          visibleRange: visibleRange,
          buffer: 4
        )
      }
    }
  }

  private func orderedAppsForDisplay() -> [RokuApp] {
    // MRU sort: most recently used first; everything else retains the provider's order.
    let indexByAppId = Dictionary(
      uniqueKeysWithValues: apps.enumerated().map { ($0.element.id, $0.offset) })

    return apps.sorted { a, b in
      let ta = cache.lastUsedAt(appId: a.id, deviceId: deviceId)
      let tb = cache.lastUsedAt(appId: b.id, deviceId: deviceId)

      switch (ta, tb) {
      case (let ta?, let tb?):
        if ta != tb { return ta > tb }
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        break
      }

      // Stable fallback to original order.
      return (indexByAppId[a.id] ?? 0) < (indexByAppId[b.id] ?? 0)
    }
  }

  private struct AppStripSlotButton: View {
      let slotIndex: Int
      let appsProvider: () -> [RokuApp]
      let deviceId: String
      let config: AppIconConfig
    let activeAppId: String?
    let glowPulseFactor: CGFloat
      let launchDelay: TimeInterval?
      let onLaunch: (RokuApp) -> Void

      @State private var capturedApp: RokuApp?

      private var currentApp: RokuApp? {
        let apps = appsProvider()
        guard slotIndex >= 0, slotIndex < apps.count else { return nil }
        return apps[slotIndex]
      }

      private var displayApp: RokuApp? { capturedApp ?? currentApp }

      var body: some View {
        guard let app = currentApp else { return AnyView(EmptyView()) }
      let isActive = (activeAppId == app.id)

      let isInput = AppIconVisual.isInput(appId: app.id, appType: app.type)

        let debugLabel = "slot=\(slotIndex) appId=\(app.id) name='\(app.name)'"

      if AppStripPlatformPolicy.usesClickToLaunch {
        // macOS: stable slots still make sense, but interaction is click-to-launch.
        return AnyView(
          AppIconButton(
            appId: app.id,
            appName: app.name,
            appType: app.type,
            deviceId: deviceId,
            config: config,
            isActiveApp: isActive,
            glowPulseFactor: glowPulseFactor,
            launchDelay: nil,
              action: { onLaunch(app) }
            )
        )
      }

        if launchDelay == nil {
          return AnyView(
            Button(action: { onLaunch(app) }) {
              AppIconVisual(
                appId: app.id,
                appName: app.name,
                appType: app.type,
                deviceId: deviceId,
                config: config,
                isActiveApp: isActive,
                glowPulseFactor: glowPulseFactor
              )
            }
            .buttonStyle(.plain)
          )
        }

        return AnyView(
          Button(action: {}) {
            AppIconVisual(
              appId: app.id,
              appName: app.name,
              appType: app.type,
              deviceId: deviceId,
              config: config,
              isActiveApp: isActive,
              glowPulseFactor: glowPulseFactor
            )
          }
          .buttonStyle(.plain)
          .sweepable(
            icon: {
              let show = displayApp ?? app
              return AppIconVisual.sweepOverlayIcon(
                appId: show.id,
                appName: show.name,
                appType: show.type,
                deviceId: deviceId,
                config: config
              )
            },
            color: isInput ? rokuPurple : AppBranding.color(for: app.name, appId: app.id),
            delay: launchDelay ?? 1.0,
            overlayDelay: 0.25,
            tooltip: "Hold to launch app channel",
            debugLabel: debugLabel,
            onPressBegan: {
              // Snapshot the current app for this slot immediately.
              capturedApp = currentApp
              if let snap = capturedApp {
                Log.debug("Sweep", "slot=\(slotIndex) captured appId=\(snap.id) name='\(snap.name)'")
              } else {
                Log.debug("Sweep", "slot=\(slotIndex) captured nil")
              }
            },
            showTooltipOnEarlyRelease: true,
            gestureStyle: .simultaneous,
            onSweepComplete: {
              let snap = capturedApp ?? currentApp
              capturedApp = nil
              guard let snap else { return }
              onLaunch(snap)
            }
        )
      )
      }
    }

  // MARK: - Empty State

  private func emptyView(sizes: IconSizes) -> some View {
    Text("No Apps Loaded...")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(
        width: direction == .vertical ? sizes.stripSize : nil,
        height: direction == .horizontal ? sizes.stripSize : nil
      )
  }

  // MARK: - Size Calculations

  fileprivate struct IconSizes {
    let iconWidth: CGFloat
    let iconHeight: CGFloat
    let labelFont: CGFloat
    let cornerRadius: CGFloat
    let cellSize: CGFloat
    let stripSize: CGFloat
  }

  private var platformShowShadow: Bool {
    AppStripPlatformPolicy.showShadow
  }

  private var screenDimension: CGFloat {
    let bounds = PlatformScreen.mainBounds
    let dim = direction == .horizontal ? bounds.height : bounds.width
    return dim > 0 ? dim : 400
  }

  private var platformExtraHeight: CGFloat {
    guard direction == .horizontal else { return 0 }
    return haloVerticalPadding.top + haloVerticalPadding.bottom
  }

  private func calculateSizes() -> IconSizes {
    let iconWidth: CGFloat
    let iconHeight: CGFloat
    let stripSize: CGFloat

    switch sizing {
    case .fixed(let w, let h):
      // Handle optional parameters with smart defaults
      if let width = w, let height = h {
        // Both specified - use as-is
        iconWidth = width
        iconHeight = height
      } else if let width = w {
        // Only width specified - compute height at 4:3 ratio (height = width * 3/4)
        iconWidth = width
        iconHeight = width * 0.75
      } else if let height = h {
        // Only height specified - compute width at 4:3 ratio (width = height * 4/3)
        iconHeight = height
        iconWidth = height * (4.0 / 3.0)
      } else {
        // Both nil - use platform default
        let d = AppStripPlatformPolicy.defaultFixedIconSize
        iconWidth = d.width
        iconHeight = d.height
      }
      let labelHeight: CGFloat = showLabels ? 20 : 0
      let cellSize = (direction == .horizontal ? iconHeight : iconWidth) + labelHeight
      stripSize = cellSize * CGFloat(lanes) + effectiveLaneSpacing * CGFloat(lanes - 1) + 8

    case .percent(let pct):
      let screenDim = screenDimension
      stripSize = screenDim * (pct / 100.0)
      let singleLaneSize = (stripSize - effectiveLaneSpacing * CGFloat(lanes - 1)) / CGFloat(lanes)
      let iconHeightRatio: CGFloat = showLabels ? 0.70 : 0.90
      iconHeight = singleLaneSize * iconHeightRatio
      iconWidth = iconHeight * (4.0 / 3.0)
    }

    let labelFont = max(8, iconHeight * 0.20)
    let cornerRadius = max(4, iconHeight * 0.15)
    let labelHeight: CGFloat = showLabels ? labelFont + 4 : 0

    // For horizontal grids: cellSize is row HEIGHT (icon + label)
    // For vertical grids: cellSize is column WIDTH (just icon width)
    let cellSize: CGFloat
    if direction == .horizontal {
      cellSize = iconHeight + labelHeight
    } else {
      cellSize = iconWidth
    }

    return IconSizes(
      iconWidth: iconWidth,
      iconHeight: iconHeight,
      labelFont: labelFont,
      cornerRadius: cornerRadius,
      cellSize: cellSize,
      stripSize: stripSize
    )
  }
}

// MARK: - Convenience: Fetch from Cache
