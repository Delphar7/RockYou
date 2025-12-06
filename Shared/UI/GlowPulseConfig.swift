//
//  GlowPulseConfig.swift
//  RockYou (Shared)
//
//  Shared pulse timing constants for the active-app glow.
//

import CoreGraphics
import Foundation

enum GlowPulseConfig {
  /// Pulse cadence (start-to-start). Idle time becomes `max(0, periodSeconds - waveSeconds)`.
  static let periodSeconds: TimeInterval = 5
  /// Total duration of one visible pulse cycle (one full sine period).
  static let waveSeconds: TimeInterval = 1.5
  /// Target update rate while running the wave (only during `waveSeconds`).
  static let waveFPS: Double = 60
  static let startDelaySeconds: TimeInterval = 1

  /// iOS-only: if no user interaction for this long, pause pulses until another gesture occurs.
  static let inactivityTimeoutSeconds: TimeInterval = 10

  /// Baseline glow opacity (the "0 phase" of the wave).
  static let baseOpacity: CGFloat = 0.90
}
