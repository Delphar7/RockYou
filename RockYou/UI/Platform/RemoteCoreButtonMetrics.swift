import CoreGraphics

/// Central tuning constants for the "core remote" (the 11 button cluster around the D-pad),
/// before any `scaleFactor` is applied.
///
/// Keep these base values in one place so tweaking iPhone portrait / macOS layouts is painless.
enum RemoteCoreButtonMetrics {
  /// iPhone portrait/macOS "TopKeyButton" base size (before multiplying by `scaleFactor`).
  static let topKeyWidth: CGFloat = 90
  static let topKeyHeight: CGFloat = 60

  static let topKeyVerticalPadding: CGFloat = 8
  static let topKeyHorizontalPadding: CGFloat = 28

  /// iPhone portrait/macOS "CircleKeyButton" base sizes (before multiplying by `scaleFactor`).
  static let circleKeySize: CGFloat = 84
  static let circleKeyLargeSize: CGFloat = 96
  static let circleKeyHorizontalSpacing: CGFloat = 32
  static let circleKeyVerticalPadding: CGFloat = 2
}
