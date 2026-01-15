//
//  HapticService.swift
//  RockYou
//
//  Cross-platform haptic feedback abstraction.
//  Same call site everywhere: HapticService.play(.click)
//

import SwiftUI

// MARK: - Haptic Types

enum HapticType {
  case click      // Light tap for button presses
  case success    // Completion feedback
  case warning    // Alert/caution
  case start      // Beginning of an interaction
  case rigid  // Strong impact (heavy/hard collision)
}

// MARK: - Haptic Service

enum HapticService {
  /// Play haptic feedback appropriate to the current platform.
  static func play(_ type: HapticType) {
    // Some gesture paths can call into haptics off the main thread (e.g. custom routers).
    // UIKit/WatchKit feedback generators expect main-thread usage; ensure we always hop to main.
    if Thread.isMainThread {
      platformPlay(type)
    } else {
      DispatchQueue.main.async {
        platformPlay(type)
      }
    }
  }

  /// Play success notification feedback (distinct from impact).
  static func notifySuccess() {
    if Thread.isMainThread {
      platformNotifySuccess()
    } else {
      DispatchQueue.main.async {
        platformNotifySuccess()
      }
    }
  }

  /// Play warning notification feedback.
  static func notifyWarning() {
    if Thread.isMainThread {
      platformNotifyWarning()
    } else {
      DispatchQueue.main.async {
        platformNotifyWarning()
      }
    }
  }

  // MARK: - Platform hooks (implemented in HapticService+<OS>.swift)

  fileprivate static func platformPlay(_ type: HapticType) {
    _ = type
  }

  fileprivate static func platformNotifySuccess() {}
  fileprivate static func platformNotifyWarning() {}
}
