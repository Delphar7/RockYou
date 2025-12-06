//
//  RemoteAction.swift
//  RockYou (Shared)
//
//  Remote control actions shared between iOS and watchOS.
//

import Foundation

public enum RemoteAction: String, Codable, CaseIterable, Sendable {
  // Navigation
  case up, down, left, right, ok
  case back, home, options

  // Playback
  case rewind, playPause, forward
  case instantReplay

  // Volume & Power
  case volumeUp, volumeDown, volumeMute
  case power

  // Input
  case search, keyboard

  /// The ECP keypress name for this action
  var ecpKey: String {
    switch self {
    case .up: return "Up"
    case .down: return "Down"
    case .left: return "Left"
    case .right: return "Right"
    case .ok: return "Select"
    case .back: return "Back"
    case .home: return "Home"
    case .options: return "Info"
    case .rewind: return "Rev"
    case .playPause: return "Play"
    case .forward: return "Fwd"
    case .instantReplay: return "InstantReplay"
    case .volumeUp: return "VolumeUp"
    case .volumeDown: return "VolumeDown"
    case .volumeMute: return "VolumeMute"
    case .power: return "Power"
    case .search: return "Search"
    case .keyboard: return "Lit_"
    }
  }
}
