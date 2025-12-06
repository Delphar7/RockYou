//
//  AppStripScrollView+iOS.swift
//  RockYou (Shared)
//
//  iOS-specific scroll view wrapper for AppStrip.
//

import SwiftUI

/// iOS implementation of the `AppStripScrollView`
struct AppStripScrollView<Content: View>: View {
  let content: Content
  let axis: Axis.Set
  let direction: AppStripDirection
  let deviceId: String
  let onScrollGestureChanged: (Bool) -> Void

  var body: some View {
    IOSAppStripScrollView(
      content: content,
      axis: axis,
      direction: direction,
      deviceId: deviceId,
      onScrollGestureChanged: onScrollGestureChanged
    )
  }
}

struct IOSAppStripScrollView<Content: View>: View {
  let content: Content
  let axis: Axis.Set
  let direction: AppStripDirection
  let deviceId: String
  let onScrollGestureChanged: (Bool) -> Void

  @State private var isScrollGestureActive = false

  var body: some View {
    ScrollView(axis, showsIndicators: false) {
      content
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 8)
        .onChanged { _ in
          if !isScrollGestureActive {
            isScrollGestureActive = true
            emitScrollGestureChanged(true)
          }
        }
        .onEnded { _ in
          isScrollGestureActive = false
          emitScrollGestureChanged(false)
        }
    )
  }

  private func emitScrollGestureChanged(_ active: Bool) {
    DebugBuild.run {
      Log.gestureTimeline(
        "AppStrip",
        "scrollGesture",
        [
          "platform": "iOS",
          "active": active ? "true" : "false",
          "deviceId": deviceId,
          "direction": direction == .horizontal ? "horizontal" : "vertical",
        ]
      )
    }
    onScrollGestureChanged(active)
  }
}
