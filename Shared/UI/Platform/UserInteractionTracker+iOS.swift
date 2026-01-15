
import Combine
import Foundation

/// Lightweight, permission-free "user touched the screen" tracker.
/// This intentionally does NOT use sensors (CoreMotion).
@MainActor
final class UserInteractionTracker: ObservableObject {
  static let shared = UserInteractionTracker()

  @Published private(set) var lastInteractionAt: Date = Date()

  private init() {}

  func noteInteraction(at date: Date = Date()) {
    lastInteractionAt = date
  }
}
