// AnimationConfigs.swift
// RockYou/UI/Dome
//
// Pure data configuration structs for dome animations.
// Used by both production code and playground.
// Each algorithm defines its config here; playground engines wrap these for UI.

import Foundation

// MARK: - Animation Enum

/// Dome animation with associated configuration.
/// Used by IrisContent (production) and playground engines.
enum DomeAnimation {
  case iris(IrisAnimationConfig)
  // Future: case ripple(RippleAnimationConfig)
  // Future: case explode(ExplodeAnimationConfig)
  // Future: case confetti(ConfettiAnimationConfig)
}

// MARK: - Iris Animation Config

/// Configuration for iris mechanism animation.
/// Dome fragments form rotating iris blades that open/close.
struct IrisAnimationConfig {
  /// Number of tessellated dome fragments
  var fragmentCount: Int = 30000

  /// Dome radius in meters
  var domeRadius: Float = 0.5

  /// Number of iris blades
  var bladeCount: Int = 12

  /// Twist angle from apex to equator (degrees)
  var twistDegrees: Float = 0.0

  /// Duration of open animation (seconds)
  var openDuration: Float = 4.0

  /// Whether to render seam ribbons between blades
  var showSeamRibbons: Bool = true

  /// Whether to show debug DPad texture
  var showDpadTexture: Bool = false

  // MARK: - Presets

  static let `default` = IrisAnimationConfig()

  /// Randomized config for production variety
  static func randomized(using rng: inout some RandomNumberGenerator) -> Self {
    IrisAnimationConfig(
      fragmentCount: 30000,
      domeRadius: 0.5,
      bladeCount: [8, 10, 12, 14, 16].randomElement(using: &rng) ?? 12,
      twistDegrees: Float.random(in: -60...60, using: &rng),
      openDuration: 4.0,
      showSeamRibbons: true,
      showDpadTexture: false
    )
  }

  /// Randomized config using system RNG
  static func randomized() -> Self {
    var rng = SystemRandomNumberGenerator()
    return randomized(using: &rng)
  }
}

// MARK: - Shatter Animation Config

/// Mode for shatter animation - determines physics behavior
enum ShatterMode: String, CaseIterable {
  case explode = "Explode"    // Fragments fly outward with ballistic physics
  case confetti = "Confetti"  // Fragments flutter down with drift and tumble
}

/// Configuration for shatter (explode/confetti) animations.
/// Unified config that covers both modes - some properties only apply to certain modes.
struct ShatterAnimationConfig {
  /// Animation mode (explode or confetti)
  var mode: ShatterMode = .explode

  /// Number of tessellated dome fragments
  var fragmentCount: Int = 50000

  /// Dome radius in meters
  var domeRadius: Float = 0.5

  // MARK: - Shared Physics

  /// Base gravity multiplier
  var baseGravity: Float = 0.2

  /// Gravity variation range
  var gravityMin: Float = 0.5
  var gravityMax: Float = 1.5

  /// Spin/tumble rate range
  var spinRateMin: Float = 4.0
  var spinRateMax: Float = 8.0

  // MARK: - Wave Propagation

  /// Whether wave propagation is enabled
  var waveEnabled: Bool = true

  /// Wave propagation speed
  var waveSpeed: Float = 2.0

  // MARK: - Explode Mode Properties

  /// Outward velocity (explode mode)
  var baseSpeed: Float = 0.15

  /// Random spread angle (explode mode)
  var spreadAngle: Float = 0.1

  /// Upward velocity component (explode mode)
  var upwardBias: Float = 0.05

  // MARK: - Confetti Mode Properties

  /// Initial upward velocity (confetti mode)
  var cannonPower: Float = 0.0

  // MARK: - Debug

  /// Whether to show debug DPad texture
  var showDpadTexture: Bool = true

  // MARK: - Presets

  static let `default` = ShatterAnimationConfig()

  static var explodeDefault: ShatterAnimationConfig {
    var config = ShatterAnimationConfig()
    config.mode = .explode
    return config
  }

  static var confettiDefault: ShatterAnimationConfig {
    var config = ShatterAnimationConfig()
    config.mode = .confetti
    config.cannonPower = 0.5
    return config
  }
}

// MARK: - Ripple Animation Config

/// Configuration for ripple dome animation.
/// Radial sin wave from impact point, fragments detach after N waves pass, then fall.
struct RippleAnimationConfig {
  /// Number of tessellated dome fragments
  var fragmentCount: Int = 50000

  /// Dome radius in meters
  var domeRadius: Float = 0.5

  // MARK: - Wave Properties

  /// How many wave cycles visible across dome (spatial frequency)
  var waveFrequency: Float = 8.0

  /// Wave height - how much fragments move in/out
  var waveAmplitude: Float = 0.006

  /// How fast waves expand outward from origin
  var rippleSpeed: Float = 0.1

  // MARK: - Physics

  /// Base gravity multiplier
  var baseGravity: Float = 0.2

  /// Gravity variation range
  var gravityMin: Float = 0.5
  var gravityMax: Float = 1.5

  /// Spin/tumble rate range
  var spinRateMin: Float = 4.0
  var spinRateMax: Float = 8.0

  /// How fast collapse wave propagates (legacy, kept for compatibility)
  var collapseSpeed: Float = 0.3

  // MARK: - Debug

  /// Whether to show debug DPad texture
  var showDpadTexture: Bool = true

  // MARK: - Presets

  static let `default` = RippleAnimationConfig()
}

// MARK: - Scene Config

/// Fixed configuration for dome scene layout and camera animation.
/// Used by DoorsView for production rendering.
enum DomeSceneConfig {
  static let baseDomeRadius: Float = 0.5
  static let domeRadius: Float = baseDomeRadius

  /// Used by LockableDPadView to size the dome render canvas relative to the DPad.
  static let renderCanvasScale: Float = 1.25

  /// Ellipse height scale (from LockableDPadView: dpadSize * 1.1)
  static let ellipseHeightScale: Float = 1.24

  /// Scale factor for dome entity to fit within ellipse
  static let domeEntityScale: Float = ellipseHeightScale / renderCanvasScale

  /// Duration of open animation (seconds) - matches LockableDPadView's openDurationSeconds
  static let openDuration: Float = 8.0

  /// Base pixel size used by RockYouApp+macOS to compute render backing size.
  /// This is a UI/layout constant, not part of the iris math.
  static let dpadRenderSize: Float = 520

  static let cameraFovDegrees: Float = 50

  // Camera animation: orbits 180° while lifting from angled to top-down
  static let cameraStartYawDegrees: Float = 180    // Starting yaw (progress=0)
  static let cameraOrbitDegrees: Float = 180       // Amount to orbit during animation
  static let cameraStartPitchDegrees: Float = 45   // Starting pitch (angled view)
  static let cameraEndPitchDegrees: Float = 90     // Ending pitch (straight down)
  static let cameraDistance: Float = 1.25          // Constant distance from center
}
