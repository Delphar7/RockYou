//
//  DisabledControlTooltip.swift
//  RockYou (Shared)
//
//  A small helper to keep "disabled-with-tooltip" behavior consistent across the app.
//

import SwiftUI

public enum HardwareControlsAvailability {
  public static let unavailableMessage =
    "Power and volume require a paired TV.  Open Configure to create a Roku/TV pair."
}

private struct DisabledControlGlobalFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let next = nextValue()
    if next != .zero { value = next }
  }
}

extension View {
  /// When `isEnabled` is false, visually dims the view and intercepts taps to show a tooltip.
  ///
  /// Note: we do **not** use `.disabled(true)` because that prevents receiving taps.
  public func disabledWithTooltip(isEnabled: Bool, message: String) -> some View {
    modifier(DisabledWithTooltipModifier(isEnabled: isEnabled, message: message))
  }

  /// Convenience wrapper for the common "hardware controls unavailable" case.
  public func disabledForUnavailableHardwareControls(isAvailable: Bool) -> some View {
    disabledWithTooltip(
      isEnabled: isAvailable,
      message: HardwareControlsAvailability.unavailableMessage
    )
  }
}

private struct DisabledWithTooltipModifier: ViewModifier {
  let isEnabled: Bool
  let message: String

  @State private var globalFrame: CGRect = .zero

  func body(content: Content) -> some View {
    content
      // Ensure custom ButtonStyles (e.g. MaterialButtonEffect) can see disabled state,
      // even though we don't use `.disabled(true)` (we still want to receive taps for tooltips).
      .environment(\.isEnabled, isEnabled)
      // When disabled, install a no-op sweep target to prevent the window-level sweep router
      // from picking sweepables behind this control (e.g. AppStrip icons under the top bar).
      .platformTouchSweepBlocker(isActive: !isEnabled, debugLabel: "disabledWithTooltip")
      // Important: apply hit-testing to the *base* content only (before we add the overlay),
      // so the overlay can still receive taps when disabled.
      .allowsHitTesting(isEnabled)
      .opacity(isEnabled ? 1.0 : 0.35)
      .overlay(
        Group {
          if !isEnabled {
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture {
                TooltipManager.shared.show(message, buttonFrame: globalFrame)
              }
          }
        }
      )
      .background(
        GeometryReader { geo in
          Color.clear.preference(
            key: DisabledControlGlobalFrameKey.self, value: geo.frame(in: .global))
        }
      )
      .onPreferenceChange(DisabledControlGlobalFrameKey.self) { globalFrame = $0 }
  }
}
