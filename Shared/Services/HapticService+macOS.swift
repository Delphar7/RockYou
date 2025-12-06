import SwiftUI

import AppKit

extension HapticService {
  fileprivate static func platformPlay(_ type: HapticType) {
    _ = type
    // Optional: we could use NSHapticFeedbackManager here, but for now keep macOS as no-op.
  }

  fileprivate static func platformNotifySuccess() {}
  fileprivate static func platformNotifyWarning() {}
}
