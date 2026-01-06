//
//  Styles.swift
//  RockYou (Shared)
//
//  Unified styling constants and modifiers for consistent appearance across platforms.
//  Includes colors, opacities, font sizes, and button styling.
//

import SwiftUI

// MARK: - Brand Colors

/// Roku purple baseline used for the app UI.
///
/// Calibrated from D-pad face swatches:
/// - mid-tone face (flat under stick) ≈ `#6C409F`  ← used as `rokuPurple`
/// - darker face (lower-left) ≈ `#683CA0`
/// - lighter face (upper-right) ≈ `#8D54C8`
///
/// The intent is that in-code lighting can push this base toward the lighter extreme
/// without the *base* fill starting out too bright.
let rokuPurple = Color(hex: 0x6C409F)

/// Dark Roku purple (matches the D-pad face “darker” sample).
///
/// Prefer using this (or other explicit colors) over `.opacity(...)` when you want “darker buttons”.
/// Alpha interacts with the material blend modes and can wash out the lighting.
let rokuDarkPurple = Color(hex: 0x3e1f69)

/// Light Roku purple - blended with white for visibility on dark backgrounds
/// Computed as ~70% white + ~30% rokuPurple for better contrast
let rokuLightPurple = Color(hex: 0xD3C6E2)

/// Power button dark green (for OFF state)
let powerButtonDarkGreen = Color(red: 0.2, green: 0.6, blue: 0.20)

// MARK: - Opacity Constants

/// Opacity levels for consistent transparency across the app
enum AppOpacity {
  static let verySubtle: Double = 0.05    // Very faint backgrounds
  static let subtle: Double = 0.1         // Subtle backgrounds, dividers
  static let light: Double = 0.15         // Light overlays, shadows
  static let medium: Double = 0.2        // Medium backgrounds, borders
  static let mediumLight: Double = 0.25  // Medium-light overlays
  static let standard: Double = 0.3      // Standard overlays, strokes
  static let moderate: Double = 0.4      // Moderate backgrounds
  static let semiOpaque: Double = 0.5     // Semi-opaque overlays
  static let twoThirds: Double = 0.66     // Two-thirds opacity (also used for reduced visibility)
  static let secondary: Double = 0.7     // Secondary text, backgrounds
  static let primary: Double = 0.8       // Primary text, backgrounds
  static let nearlyOpaque: Double = 0.92  // Nearly opaque (consolidated from 0.9, 0.92, 0.95)
}

// MARK: - Font Sizes

/// Standard font sizes for consistent typography
/// Note: Sizes within 1pt have been consolidated (8-9→8, 12-13→12, 13-14→13)
enum AppFontSize {
  static let tiny: CGFloat = 8           // Tiny labels (consolidated from 8-9)
  static let small: CGFloat = 10        // Small labels
  static let compact: CGFloat = 11      // Compact text
  static let caption: CGFloat = 12      // Caption text (consolidated from 12-13)
  static let body: CGFloat = 13         // Body text (consolidated from 13-14)
  static let medium: CGFloat = 16       // Medium text
  static let large: CGFloat = 17  // Large text
  static let veryLarge: CGFloat = 26    // Very large text
  static let iconSmall: CGFloat = 32     // Small icons
  static let iconMedium: CGFloat = 40    // Medium icons
  static let iconLarge: CGFloat = 48     // Large icons
  static let iconXLarge: CGFloat = 50    // Extra large icons
}

// MARK: - App Button Styling
//
// Implemented in `Styles+watchOS.swift` and `Styles+nonWatch.swift` to avoid `#if` branching in this file.

// MARK: - Capsule Badges

extension View {
  /// Standard Roku purple capsule badge used across the app (e.g. paired device pills).
  ///
  /// Uses `background(_:in:)` so the fill is clipped to the capsule shape.
  func rokuPurpleCapsuleBadge(
    leading: CGFloat? = nil,
    trailing: CGFloat? = nil,
    horizontal: CGFloat = 8,
    vertical: CGFloat = 4
  ) -> some View {
    self
      .padding(.leading, leading ?? horizontal)
      .padding(.trailing, trailing ?? horizontal)
      .padding(.vertical, vertical)
      .background(rokuPurple, in: Capsule())
  }
}
