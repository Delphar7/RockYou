//
//  SafePowerButton.swift
//  RockYou
//
//  Power button using .sweepable() modifier for hold-to-confirm.
//  Unified for iOS and watchOS - reads from DeviceStateManager.
//

import SwiftUI

// MARK: - Platform-neutral pair state

struct SafePowerButtonPairState {
  let isPaired: Bool
  let isMixed: Bool
  let tvId: String?
  let streamerId: String?
  let tvMode: PowerMode
  let streamerMode: PowerMode?
}

// MARK: - Button Style Configuration

enum PowerButtonStyle {
  /// Compact: icon only, 30pt height (for NavPage, MediaPage)
  case compact
  /// Labeled: icon + "Power" text, 48pt height (for QuickActionsPage)
  case labeled
  /// Custom height with optional label
  case custom(height: CGFloat, showLabel: Bool)

  var height: CGFloat {
    switch self {
    case .compact: return 30
    case .labeled: return 48
    case .custom(let h, _): return h
    }
  }

  var showLabel: Bool {
    switch self {
    case .compact: return false
    case .labeled: return true
    case .custom(_, let show): return show
    }
  }

  var iconSize: CGFloat {
    if showLabel {
      return 18  // Fixed for labeled buttons
    }
    // Scale icon to ~40% of button height, clamped
    return min(28, max(14, height * 0.4))
  }
}

// MARK: - Unified Safe Power Button

/// Power button that reads state from DeviceStateManager (shared on all platforms)
/// Uses .sweepable() modifier when device is ON (needs safety delay to turn off)
struct SafePowerButton: View {
  let onPower: () -> Void
  var style: PowerButtonStyle = .compact
  var safetyDelay: TimeInterval? = 2.0  // Default 2s for power

  struct SweepPressedReader<Content: View>: View {
    @Environment(\.sweepPressed) private var sweepPressed
    let content: (Bool) -> Content

    var body: some View {
      content(sweepPressed)
    }
  }

  // MARK: - Device ID (unified via DeviceSelectionProvider)

  private var selectedDeviceId: String? {
    DeviceSelectionProvider.selectedDeviceId
  }

  // MARK: - Power State

  @MainActor
  private var pairState: SafePowerButtonPairState {
    SafePowerButtonPlatform.pairState(selectedDeviceId: selectedDeviceId)
  }

  private func foregroundColor(for mode: PowerMode) -> Color {
    mode.isOn ? .white : powerButtonDarkGreen
  }
  private func backgroundColor(for mode: PowerMode) -> Color {
    mode.isOn
      ? Color.red.opacity(AppOpacity.primary) : Color.white.opacity(AppOpacity.nearlyOpaque)
  }
  private func strokeColor(for mode: PowerMode) -> Color {
    mode.isOn
      ? Color.white.opacity(AppOpacity.standard)
      : Color.red.opacity(AppOpacity.primary)
  }

  private var requiresSweep: Bool {
    pairState.tvMode.isOn
  }

  private var powerSeed: UInt64 { "POWER".stableHash64 }

  // MARK: - Button Content

  @ViewBuilder
  private var powerLabel: some View {
    Group {
      if style.showLabel {
        VStack(spacing: 2) {
          Image(systemName: "power")
            .font(.system(size: style.iconSize, weight: .semibold))
          Text("Power")
            .font(.system(size: AppFontSize.small, weight: .medium))
        }
      } else {
        Image(systemName: "power")
          .font(.system(size: style.iconSize, weight: .semibold))
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: style.height)
    .foregroundStyle(foregroundColor(for: pairState.tvMode))
  }

  @ViewBuilder
  private var buttonContent: some View {
    let tvMode = pairState.tvMode
    let streamerMode = pairState.streamerMode ?? tvMode
    let isMixed = pairState.isMixed
    let shape = Capsule()
    let base =
      Group {
        if style.showLabel {
          VStack(spacing: 2) {
            Image(systemName: "power")
              .font(.system(size: style.iconSize, weight: .semibold))
            Text("Power")
              .font(.system(size: AppFontSize.small, weight: .medium))
          }
        } else {
          Image(systemName: "power")
            .font(.system(size: style.iconSize, weight: .semibold))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: style.height)
      // Background/overlay should be clipped to the capsule shape; use background(in:) instead of
      // applying `.background` after `.clipShape` (which would render outside the clip).
      .contentShape(Rectangle())
      .appButtonShadow(radius: 4, opacity: 0.15)

    if isMixed {
      let fg = LinearGradient(
        colors: [foregroundColor(for: tvMode), foregroundColor(for: streamerMode)],
        startPoint: .top,
        endPoint: .bottom
      )
      let bg = LinearGradient(
        colors: [backgroundColor(for: tvMode), backgroundColor(for: streamerMode)],
        startPoint: .top,
        endPoint: .bottom
      )
      let st = LinearGradient(
        colors: [strokeColor(for: tvMode), strokeColor(for: streamerMode)],
        startPoint: .top,
        endPoint: .bottom
      )

      base
        .foregroundStyle(fg)
        .background(bg, in: shape)
        .overlay(st, in: shape.stroke(lineWidth: 1))
        .clipShape(shape)
    } else {
      let fg = foregroundColor(for: tvMode)
      let bg = backgroundColor(for: tvMode)
      let st = strokeColor(for: tvMode)

      // Note: iOS/macOS power uses `MaterialButtonEffect` directly in `body` so the glyph can animate
      // with the chrome during sweep holds, and so the OFF state is a real `Button`.
      // This branch exists primarily for watchOS (and as a simple fallback).
      base
        .foregroundStyle(fg)
        .background(bg, in: shape)
        .overlay(st, in: shape.stroke(lineWidth: 1))
        .clipShape(shape)
    }
  }

  // MARK: - Body

  var body: some View {
    // Mixed pair state:
    // - Tap (quick release, before overlay): turn ON any OFF device(s) in the pair.
    // - Hold to completion: turn OFF any ON device(s) in the pair.
    // - Early release after overlay begins: show a tooltip explaining both actions.
    if pairState.isMixed, let safetyDelay, safetyDelay > 0 {
      buttonContent
        .sweepable(
          icon: "power",
          color: .red,
          delay: safetyDelay,
          overlayDelay: 1.0 / 3.0,
          tooltip:
            "Tap the power button to turn on both devices, hold down to turn off both devices.",
          quickTapPolicy: .onlyIfOverlayNotShown,
          onQuickTap: SafePowerButtonPlatform.mixedQuickTap(pairState: pairState, onPower: onPower),
          onSweepComplete: SafePowerButtonPlatform.mixedSweepComplete(pairState: pairState, onPower: onPower)
        )
    } else if pairState.isMixed {
      // Degenerate fallback (no safety delay): behave like "power on" tap.
      let bg = backgroundColor(for: pairState.tvMode)
      SafePowerButtonPlatform.normalOffView(
        buttonContent: buttonContent,
        powerLabel: powerLabel,
        backgroundColor: bg,
        seed: powerSeed,
        onPower: SafePowerButtonPlatform.mixedQuickTap(pairState: pairState, onPower: onPower)
      )
    } else if requiresSweep, let safetyDelay, safetyDelay > 0 {
      // Normal ON behavior - use sweep for safety.
      let bg = backgroundColor(for: pairState.tvMode)
      SafePowerButtonPlatform.requiresSweepView(
        buttonContent: buttonContent,
        powerLabel: powerLabel,
        backgroundColor: bg,
        seed: powerSeed,
        safetyDelay: safetyDelay,
        onPower: onPower
      )
    } else {
      // Normal OFF behavior - simple tap to turn on.
      let bg = backgroundColor(for: pairState.tvMode)
      SafePowerButtonPlatform.normalOffView(
        buttonContent: buttonContent,
        powerLabel: powerLabel,
        backgroundColor: bg,
        seed: powerSeed,
        onPower: onPower
      )
    }
  }
}
