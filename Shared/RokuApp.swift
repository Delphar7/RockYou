//
//  RokuApp.swift
//  RockYou (Shared)
//
//  Model for a Roku app/channel. Shared across all platforms.
//

import Foundation

/// Roku app/channel model
struct RokuApp: Identifiable, Codable, Hashable, Sendable {
  let id: String        // App ID (e.g., "12", "2285")
  let name: String      // Display name (e.g., "Netflix", "Hulu")
  let type: String?     // App type (e.g., "appl", "menu", "tvin")
  let version: String?  // App version
  let deviceId: String? // Which device this app belongs to (optional for backward compat)

  /// Initialize with all fields
  init(id: String, name: String, type: String?, version: String?, deviceId: String? = nil) {
    self.id = id
    self.name = name
    self.type = type
    self.version = version
    self.deviceId = deviceId
  }

  /// Icon filename for disk cache: {deviceId}_{appId}.png
  func iconFilename(for deviceId: String) -> String {
    "\(deviceId)_\(id).png"
  }

  /// Check if this is a TV input (HDMI, AV, Tuner) rather than an app
  var isInput: Bool {
    // Type "tvin" indicates TV input, or fallback to name detection
    if let type = type, type == "tvin" {
      return true
    }
    let lower = name.lowercased()
    return lower.contains("hdmi") ||
           lower.contains("tuner") ||
           lower.contains("antenna") ||
           lower.hasPrefix("av") ||
           lower.contains(" av")
  }
}
