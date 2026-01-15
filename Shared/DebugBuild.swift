import Foundation
import CoreFoundation
import SwiftUI

/// Centralized debug-build gates so we can avoid sprinkling `#if DEBUG` across the codebase.
enum DebugBuild {
  static var isEnabled: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }

  /// Runs `work` only in Debug builds.
  static func run(_ work: () -> Void) {
    #if DEBUG
      work()
    #endif
  }

  /// In some simulator install flows `cfprefsd` can briefly serve stale values.
  /// This forces a sync for the current app's preferences domain (debug-only).
  static func syncCurrentAppPreferences() {
    run { CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication) }
  }

  /// Flush `UserDefaults` to disk (debug-only).
  static func flushUserDefaults() {
    run { UserDefaults.standard.synchronize() }
  }
}

// MARK: - Debug UI utilities

/// Shared state for one-time-only invariant checks (prevents repeated alerts for same issue).
private enum DebugCrashAlertState {
  @MainActor static var reportedKeys: Set<String> = []
}

/// Debug-only invariant checker that shows a modal alert and then crashes on demand.
///
/// This avoids needing a debugger to understand why an app won't proceed, while still forcing
/// the issue to be addressed.
///
/// Can be used as:
/// 1. **Modifier** via `.debugCrashAlertOnAppear(check:)` - runs check on appear
/// 2. **Standalone View** via `DebugCrashAlertView(title:message:)` - triggered by binding
struct DebugCrashAlertModifier: ViewModifier {
  let title: String
  let check: () -> String?

  @State private var message: String? = nil

  func body(content: Content) -> some View {
    content
      .onAppear {
        guard !DebugCrashAlertState.reportedKeys.contains(title) else { return }
        DebugCrashAlertState.reportedKeys.insert(title)

        guard let msg = check() else { return }

        if DebugBuild.isEnabled {
          message = msg
        } else {
          // Release: log only (no UI, no crash).
          Log.error("Invariant", msg)
        }
      }
      .alert(
        title,
        isPresented: Binding(
          get: { message != nil },
          set: { if !$0 { message = nil } }
        )
      ) {
        Button("Crash") {
          fatalError(message ?? "\(title) (no details)")
        }
      } message: {
        Text(message ?? "")
      }
  }
}

/// Standalone view that shows a debug crash alert when `message` binding is non-nil.
/// Use when the error is detected asynchronously (e.g., after model load).
struct DebugCrashAlertView: View {
  let title: String
  @Binding var message: String?

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onChange(of: message) { _, newValue in
        guard let msg = newValue else { return }
        guard !DebugCrashAlertState.reportedKeys.contains(title) else { return }
        DebugCrashAlertState.reportedKeys.insert(title)

        if !DebugBuild.isEnabled {
          Log.error("Invariant", msg)
          message = nil  // Clear in release so it doesn't persist
        }
      }
      .alert(
        title,
        isPresented: Binding(
          get: { DebugBuild.isEnabled && message != nil },
          set: { if !$0 { message = nil } }
        )
      ) {
        Button("Crash") {
          fatalError(message ?? "\(title) (no details)")
        }
      } message: {
        Text(message ?? "")
      }
  }
}

extension View {
  /// Runs `check` in Debug builds on appear; if it returns a message, presents an alert with a
  /// single "Crash" button that terminates the process via `fatalError`.
  func debugCrashAlertOnAppear(
    title: String = "Invariant Violation", check: @escaping () -> String?
  )
    -> some View
  {
    modifier(DebugCrashAlertModifier(title: title, check: check))
  }

  /// Attaches a debug crash alert that triggers when `message` becomes non-nil.
  /// Use when the error is detected asynchronously.
  func debugCrashAlert(title: String = "Invariant Violation", message: Binding<String?>) -> some View {
    self.background(DebugCrashAlertView(title: title, message: message))
  }
}
