// AnimationConfigs.swift
// RockYou/UI/Dome
//
// Pure data configuration structs for dome animations.
// Used by both production code and playground.
// Each algorithm defines its config here; playground engines wrap these for UI.

import Foundation

// MARK: - Animation Enum

/// Dome animation with associated configuration.
/// Production effects use iris, shatter, ripple, and flower.
enum DomeAnimation {
  case iris(IrisAnimationConfig)
  case shatter(ShatterAnimationConfig)
  case ripple(RippleAnimationConfig)
  case flower(FlowerAnimationConfig)
}

// MARK: - Iris Animation Config

/// Configuration for iris mechanism animation.
/// Uses dot(Q, n_i) > threshold (half-space checks) for blade coverage.
/// Supports spiral seams via tilt parameter and cheaper per-fragment computation.
struct IrisAnimationConfig {
  /// Number of tessellated dome fragments
  var fragmentCount: Int = 30000

  /// Dome radius in meters
  var domeRadius: Float = 0.5

  /// Number of iris blades
  var bladeCount: Int = 12

  /// Shader time budget (seconds). Wall-clock duration is DomeSceneConfig.duration.
  var openDuration: Float = 2.5

  /// Tilt angle in radians: 0 = radial (no spiral), π/2 = full tangential.
  /// Range 0.3...0.8 ≈ 17°...46°.
  var tilt: Float = 0.5

  /// Elevation in radians: lifts blade normals toward dome apex.
  /// Encoded to GPU as [0, π/4]. Range 0.4...0.6 ≈ 22.9°...34.4°.
  var elevation: Float = 0.5

  /// Whether to render seam ribbons between blades
  var showSeamRibbons: Bool = true

  // MARK: - Presets

  static let `default` = IrisAnimationConfig()

  /// Randomized config for production variety
  static func randomized(using rng: inout some RandomNumberGenerator) -> Self {
    IrisAnimationConfig(
      bladeCount: [8, 10, 12, 14, 16].randomElement(using: &rng) ?? 12,
      tilt: Float.random(in: 0.3...0.8, using: &rng),
      elevation: Float.random(in: 0.4...0.6, using: &rng)
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

  /// Shader time budget (seconds). Wall-clock duration is DomeSceneConfig.duration.
  var openDuration: Float = 4.0

  // MARK: - Debug

  /// Whether to show debug DPad texture
  var showDpadTexture: Bool = false

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

  /// Randomized config for production variety
  static func randomized(using rng: inout some RandomNumberGenerator) -> Self {
    let mode: ShatterMode = Bool.random(using: &rng) ? .explode : .confetti
    var config = ShatterAnimationConfig(mode: mode)
    config.baseGravity = Float.random(in: 0.15...0.5, using: &rng)
    config.baseSpeed = Float.random(in: 0.1...0.25, using: &rng)
    config.waveSpeed = Float.random(in: 2.0...3.5, using: &rng)
    config.cannonPower = mode == .confetti ? Float.random(in: 0.4...0.8, using: &rng) : 0.0
    return config
  }

  /// Randomized config using system RNG
  static func randomized() -> Self {
    var rng = SystemRandomNumberGenerator()
    return randomized(using: &rng)
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

  /// How fast waves expand outward from origin (0.2 = reaches far side in 5s)
  var rippleSpeed: Float = 0.2

  /// Shader time budget (seconds). Wall-clock duration is DomeSceneConfig.duration.
  var openDuration: Float = 5.0

  // MARK: - Physics

  /// Base gravity multiplier
  var baseGravity: Float = 0.2

  /// Gravity variation range
  var gravityMin: Float = 0.5
  var gravityMax: Float = 2.0

  /// Spin/tumble rate range
  var spinRateMin: Float = 4.0
  var spinRateMax: Float = 8.0

  // MARK: - Debug

  /// Whether to show debug DPad texture
  var showDpadTexture: Bool = false

  // MARK: - Presets

  static let `default` = RippleAnimationConfig()

  /// Randomized config for production variety
  static func randomized(using rng: inout some RandomNumberGenerator) -> Self {
    RippleAnimationConfig(
      waveFrequency: Float.random(in: 4...8, using: &rng),
      waveAmplitude: Float.random(in: 0.005...0.012, using: &rng),
      rippleSpeed: Float.random(in: 0.2...0.3, using: &rng)
    )
  }

  /// Randomized config using system RNG
  static func randomized() -> Self {
    var rng = SystemRandomNumberGenerator()
    return randomized(using: &rng)
  }
}

// MARK: - Flower Animation Config

/// Configuration for blooming flower blade animation.
/// Iris blades on a dome that rotate open like a flower.
struct FlowerAnimationConfig {
  /// Number of iris blades
  var bladeCount: Int = 10

  /// How far blades extend from rim toward pole (0 = rim only, 1 = to pole)
  var bladeCoverage: Float = 0.85

  /// Angular overlap between adjacent blades (radians)
  var bladeOverlap: Float = 0.02

  /// Dome radius in meters
  var domeRadius: Float = 0.5

  /// Shader time budget (seconds). Wall-clock duration is DomeSceneConfig.duration.
  var openDuration: Float = 2.5

  // MARK: - Presets

  static let `default` = FlowerAnimationConfig()

  /// Randomized config for production variety
  static func randomized(using rng: inout some RandomNumberGenerator) -> Self {
    FlowerAnimationConfig(
      bladeCount: [10, 12, 14, 16, 18].randomElement(using: &rng) ?? 10,
      bladeCoverage: Float.random(in: 0.75...0.95, using: &rng),
      bladeOverlap: Float.random(in: 0.01...0.04, using: &rng)
    )
  }

  /// Randomized config using system RNG
  static func randomized() -> Self {
    var rng = SystemRandomNumberGenerator()
    return randomized(using: &rng)
  }
}

// MARK: - Scene Config

/// Fixed configuration for dome scene layout and camera animation.
/// Used by DoorsView for production rendering.
enum DomeSceneConfig {
  /// Wall-clock duration for the main animation phase (seconds).
  /// At progress=1 the DPad surfaces. Shader time = progress × max(openDuration, duration).
  static let duration: Float = 5.0

  /// Used by LockableDPadView to size the dome render canvas relative to the DPad.
  static let renderCanvasScale: Float = 1.25

  /// Ellipse height scale (from LockableDPadView: dpadSize * 1.1)
  static let ellipseHeightScale: Float = 1.24

  /// Scale factor for dome entity to fit within ellipse
  static let domeEntityScale: Float = ellipseHeightScale / renderCanvasScale

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
