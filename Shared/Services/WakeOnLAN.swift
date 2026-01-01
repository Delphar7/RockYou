//
//  WakeOnLAN.swift
//  RockYou (Shared)
//
//  Cross-platform Wake-on-LAN helper.
//
//  NOTE:
//  - The actual UDP broadcast sending lives in platform files:
//      - `WakeOnLANPlatform+nonWatch.swift` (iOS + macOS)
//      - `WakeOnLANPlatform+watchOS.swift` (stub)
//

import Foundation

/// Wake-on-LAN (WoL) magic packet sender.
///
/// This is intentionally best-effort:
/// - WoL has no acknowledgements.
/// - A device that doesn't wake could be unplugged, on a different network, or not configured for WoL.
public enum WakeOnLAN {
  public enum SendResult: Sendable, Equatable {
    case sent(count: Int)
    case noValidMACs
    case notSupportedOnThisPlatform
  }

  /// Send WoL magic packets to all provided MAC addresses.
  ///
  /// - Parameters:
  ///   - macAddresses: MAC addresses in common formats (`AA:BB:CC:DD:EE:FF`, `AA-BB-...`, etc).
  ///   - repeats: Number of times to repeat sends (helps on some networks).
  public static func wake(macAddresses: [String], repeats: Int = 2) async -> SendResult {
    let macs = normalizeMACs(macAddresses)
    guard !macs.isEmpty else { return .noValidMACs }

    guard WakeOnLANPlatform.isSupported else {
      return .notSupportedOnThisPlatform
    }

    var total = 0
    for _ in 0..<max(1, repeats) {
      total += await WakeOnLANPlatform.sendMagicPackets(to: macs)
      // Tiny delay to avoid blasting packets back-to-back.
      try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
    }
    return .sent(count: total)
  }

  // MARK: - Helpers

  /// Normalize and dedupe MAC strings.
  static func normalizeMACs(_ input: [String]) -> [String] {
    var out: [String] = []
    var seen: Set<String> = []

    for raw in input {
      guard let norm = normalizeMAC(raw) else { continue }
      if seen.insert(norm).inserted {
        out.append(norm)
      }
    }
    return out
  }

  /// Returns a canonical MAC string of the form `aa:bb:cc:dd:ee:ff`.
  static func normalizeMAC(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Remove common separators.
    let hex = trimmed
      .replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: ".", with: "")
      .lowercased()

    guard hex.count == 12 else { return nil }
    guard hex.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else { return nil }

    // Re-insert ":" every 2 chars.
    var parts: [String] = []
    parts.reserveCapacity(6)
    var i = hex.startIndex
    for _ in 0..<6 {
      let j = hex.index(i, offsetBy: 2)
      parts.append(String(hex[i..<j]))
      i = j
    }
    return parts.joined(separator: ":")
  }
}

/// Platform-specific WoL implementation hook.
enum WakeOnLANPlatform {}
