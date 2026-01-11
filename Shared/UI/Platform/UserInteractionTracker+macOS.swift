import Combine
import Foundation

// NOTE: The idle-lock feature is iOS-only in production. This tracker exists on macOS
// purely for DEBUG testing of the BreakerSwitch unlock UI. In release builds, the
// tracker stays at .distantPast so the lock never triggers.

@MainActor
final class UserInteractionTracker: ObservableObject {
  static let shared = UserInteractionTracker()

  @Published private(set) var lastInteractionAt: Date = .distantPast

  private init() {}

  func noteInteraction(at date: Date = Date()) {
    #if DEBUG
      // Mirror iOS behavior for testing the lock/unlock flow on Mac
      lastInteractionAt = date
    #endif
    // In release: no-op, lastInteractionAt stays .distantPast, lock never triggers
  }
}
