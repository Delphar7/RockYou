//
//  DeviceInfo+WakeOnLAN.swift
//  RockYou (Shared)
//

import Foundation

public extension DeviceInfo {
  /// Wake-on-WLAN capability as a tri-state.
  ///
  /// Roku field: `supports-wake-on-wlan`.
  ///
  /// - `.yes`: field is present and truthy (or present-only).
  /// - `.no`: field is present and explicitly falsey.
  /// - `.unknown`: field missing.
  var wakeOnLANSupport: TVCapabilitySupport {
    guard let raw = properties["supports-wake-on-wlan"] else { return .unknown }
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if v.isEmpty { return .yes } // presence-only boolean
    if v == "true" || v == "1" || v == "yes" { return .yes }
    if v == "false" || v == "0" || v == "no" { return .no }
    // Unknown string: treat as unknown (avoid hard false).
    return .unknown
  }

  /// Best-known MAC addresses for WoL (normalized `aa:bb:cc:dd:ee:ff`).
  ///
  /// Roku fields commonly include `wifi-mac` and/or `ethernet-mac`.
  var wakeOnLANMacAddresses: [String] {
    let candidates: [String?] = [
      properties["wifi-mac"],
      properties["ethernet-mac"],
      // Some devices expose a generic field; keep this as a best-effort fallback.
      properties["mac"],
      properties["mac-address"],
    ]

    var out: [String] = []
    var seen: Set<String> = []
    for c in candidates {
      guard let c, let norm = WakeOnLAN.normalizeMAC(c) else { continue }
      if seen.insert(norm).inserted {
        out.append(norm)
      }
    }
    return out
  }

  /// True if we have enough info to attempt WoL.
  var canAttemptWakeOnLAN: Bool {
    wakeOnLANSupport != .no && !wakeOnLANMacAddresses.isEmpty
  }

  // Intentionally no local MAC parsing helpers here; reuse `WakeOnLAN.normalizeMAC(_:)`.
}
