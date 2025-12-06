//
//  TooltipManager.swift
//  RockYou
//
//  Shared state for fullscreen tooltip overlay.
//

import Combine
import SwiftUI

@MainActor
final class TooltipManager: ObservableObject {
  static let shared = TooltipManager()

  @Published var message: String?
  @Published var buttonFrame: CGRect = .zero
  /// Global frame (same coordinate space as `buttonFrame`) for the visible tooltip bubble.
  /// Used to avoid "dismiss-on-touch-down" from turning a tap on the tooltip into a tap on
  /// the underlying UI.
  @Published var bubbleFrame: CGRect = .zero

  private var dismissTask: Task<Void, Never>?

  func show(_ message: String, buttonFrame: CGRect, duration: TimeInterval = 10.0) {
    Log.gestureTimeline(
      "Tooltip",
      "show",
      [
        "message": message,
        "duration": String(format: "%.2f", duration),
        "buttonFrame": String(describing: buttonFrame),
      ]
    )
    self.message = message
    self.buttonFrame = buttonFrame

    dismissTask?.cancel()
    dismissTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(duration * 500_000_000))
      guard !Task.isCancelled else { return }
      self.dismiss()
    }
  }

  func dismiss() {
    dismiss(immediately: false)
  }

  func dismiss(immediately: Bool) {
    dismissTask?.cancel()
    if immediately {
      Log.gestureTimeline("Tooltip", "dismiss", ["immediately": "true"])
      message = nil
      bubbleFrame = .zero
      return
    }
    Log.gestureTimeline("Tooltip", "dismiss", ["immediately": "false"])
    withAnimation(.easeOut(duration: 0.2)) {
      message = nil
    }
    bubbleFrame = .zero
  }
}
