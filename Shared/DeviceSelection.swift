//
//  DeviceSelection.swift
//  RockYou (Shared)
//
//  Typed representation of what the user is currently controlling.
//

import Foundation

/// What the user has selected as their "primary" device.
///
/// Today the UI is still TV-oriented, but we keep this typed to support future devices
/// (e.g. StreamBar: a "streamer" that also supports volume).
public enum DeviceSelection: Codable, Equatable, Sendable {
  case tv(id: String)
  case streamer(id: String)

  public var id: String {
    switch self {
    case .tv(let id): return id
    case .streamer(let id): return id
    }
  }
}
