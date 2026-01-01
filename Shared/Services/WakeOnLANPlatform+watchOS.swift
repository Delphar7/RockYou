//
//  WakeOnLANPlatform+watchOS.swift
//  RockYou (Shared)
//
//  watchOS: Wake-on-LAN is intentionally not supported (low-level networking constraints).
//

import Foundation

extension WakeOnLANPlatform {
  static var isSupported: Bool { false }

  static func sendMagicPackets(to normalizedMACs: [String]) async -> Int {
    _ = normalizedMACs
    return 0
  }
}
