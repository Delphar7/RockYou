import SwiftUI
import UIKit

struct ContentViewHost: View {
  @ObservedObject private var watchManager = WatchConnectivityManager.shared
  @ObservedObject private var interactionTracker = UserInteractionTracker.shared

  var body: some View {
    ContentViewCore(onPlatformAction: { _ in triggerHapticTap() })
      // Observational touch tracker (no sensors) for optional UI animations.
      .background(UserInteractionObserver())
      .environment(\.glowAnimationLastUserInteractionAt, interactionTracker.lastInteractionAt)
      .alert(
        watchManager.configurationIssue?.title ?? "Configuration Issue",
        isPresented: Binding(
          get: { watchManager.configurationIssue != nil },
          set: { if !$0 { watchManager.dismissConfigurationIssue() } }
        )
      ) {
        Button("OK", role: .cancel) {
          watchManager.dismissConfigurationIssue()
        }
      } message: {
        Text(watchManager.configurationIssue?.message ?? "")
      }
  }

  private func triggerHapticTap() {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
  }
}
