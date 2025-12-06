//
//  AppStripScrollView+watchOS.swift
//  RockYou (Shared)
//
//  watchOS-specific scroll view wrapper for AppStrip
//

import SwiftUI
import WatchKit

/// watchOS implementation of the `AppStripScrollView`
struct AppStripScrollView<Content: View>: View {
  let content: Content
  let axis: Axis.Set
  let direction: AppStripDirection
  let deviceId: String
  let onScrollGestureChanged: (Bool) -> Void

  var body: some View {
    WatchAppStripScrollView(
      content: content,
      axis: axis,
      direction: direction,
      deviceId: deviceId,
      onScrollGestureChanged: onScrollGestureChanged
    )
  }
}

// MARK: - Preference: AppStrip interaction state (used for routing)

struct AppStripInteractionActivePreferenceKey: PreferenceKey {
  static var defaultValue: Bool = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

// MARK: - Watch Scroll Coordinate Space

enum WatchAppStripScrollCoordinateSpace {
  static let name = "AppStripWatchScrollSpace"
}

// MARK: - Watch Scroll Offset Preference Key

struct WatchAppStripScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct WatchAppStripScrollView<Content: View>: View {
  let content: Content
  let axis: Axis.Set
  let direction: AppStripDirection
  let deviceId: String
  let onScrollGestureChanged: (Bool) -> Void

  @State private var isScrollGestureActive = false
  @State private var lastScrollOffset: CGFloat = 0
  @State private var scrollIdleTask: Task<Void, Never>?

  var body: some View {
    ScrollView(axis, showsIndicators: false) {
      content
        .background(
          GeometryReader { geo in
            Color.clear.preference(
              key: WatchAppStripScrollOffsetPreferenceKey.self,
              value: direction == .horizontal
                ? geo.frame(in: .named(WatchAppStripScrollCoordinateSpace.name)).minX
                : geo.frame(in: .named(WatchAppStripScrollCoordinateSpace.name)).minY
            )
          }
        )
    }
    .coordinateSpace(name: WatchAppStripScrollCoordinateSpace.name)
    .onPreferenceChange(WatchAppStripScrollOffsetPreferenceKey.self) { newOffset in
      handleWatchScrollOffsetChanged(newOffset)
    }
    // Let NavPage know when the strip is actively interacting (for page-swipe gating).
    .preference(key: AppStripInteractionActivePreferenceKey.self, value: isScrollGestureActive)
  }

  private func handleWatchScrollOffsetChanged(_ newOffset: CGFloat) {
    // Ignore first update (layout establishes baseline).
    if lastScrollOffset == 0 {
      lastScrollOffset = newOffset
      return
    }

    let delta = abs(newOffset - lastScrollOffset)
    guard delta >= 0.5 else { return }
    lastScrollOffset = newOffset

    if !isScrollGestureActive {
      isScrollGestureActive = true
      emitScrollGestureChanged(true)
    }

    // Debounce: keep suppression true briefly after the last observed movement.
    scrollIdleTask?.cancel()
    scrollIdleTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)  // 0.9s
      guard !Task.isCancelled else { return }
      isScrollGestureActive = false
      emitScrollGestureChanged(false)
    }
  }

  private func emitScrollGestureChanged(_ active: Bool) {
    DebugBuild.run {
      Log.gestureTimeline(
        "AppStrip",
        "scrollGesture",
        [
          "platform": "watchOS",
          "active": active ? "true" : "false",
          "deviceId": deviceId,
          "direction": direction == .horizontal ? "horizontal" : "vertical",
        ]
      )
    }
    onScrollGestureChanged(active)
  }
}
