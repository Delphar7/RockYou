//
//  SwipeAwareButtonStyle.swift
//  RockYou
//
//  Button style that:
//  1. Delays showing "pressed" state to avoid visual glitches when swiping
//  2. Adds high-priority swipe gesture to allow page navigation across buttons
//
//  Usage:
//    .buttonStyle(.swipeAware)
//    .environment(\.onSwipeLeft, { goToPreviousPage() })
//    .environment(\.onSwipeRight, { goToNextPage() })
//

import SwiftUI

// MARK: - Environment Keys for Swipe Actions

private struct OnSwipeLeftKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

private struct OnSwipeRightKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
  var onSwipeLeft: (() -> Void)? {
    get { self[OnSwipeLeftKey.self] }
    set { self[OnSwipeLeftKey.self] = newValue }
  }

  var onSwipeRight: (() -> Void)? {
    get { self[OnSwipeRightKey.self] }
    set { self[OnSwipeRightKey.self] = newValue }
  }
}

// MARK: - Swipe Aware Button Style

/// Button style that delays pressed highlight and allows swipes to pass through.
struct SwipeAwareButtonStyle: ButtonStyle {

  func makeBody(configuration: Configuration) -> some View {
    SwipeAwareButton(configuration: configuration)
  }
}

private struct SwipeAwareButton: View {
  let configuration: ButtonStyle.Configuration

  @Environment(\.onSwipeLeft) private var onSwipeLeft
  @Environment(\.onSwipeRight) private var onSwipeRight

  // Track if we should show pressed state
  @State private var showPressed = false

  // Track if swipe gesture fired (to suppress flash on swipe)
  @State private var didSwipe = false

  // Task for delayed press highlight
  @State private var pressDelayTask: Task<Void, Never>?

  // Timing constants
  private let pressDelay: UInt64 = 250_000_000    // 250ms before showing pressed
  private let flashDuration: UInt64 = 50_000_000  // 50ms flash on quick tap

  var body: some View {
    configuration.label
      .opacity(showPressed ? 0.5 : 1.0)
      .highPriorityGesture(swipeGesture)
      .onChange(of: configuration.isPressed) { wasPressed, isPressed in
        if isPressed {
          // Finger down - reset swipe flag, start delayed highlight
          didSwipe = false
          pressDelayTask?.cancel()
          pressDelayTask = Task {
            try? await Task.sleep(nanoseconds: pressDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
              showPressed = true
            }
          }
        } else {
          // Finger up - cancel delay timer
          pressDelayTask?.cancel()
          pressDelayTask = nil

          if showPressed {
            // Was already showing pressed (held > 250ms) - just hide it
            showPressed = false
          } else if !didSwipe {
            // Quick tap (< 250ms) and not a swipe - flash briefly
            showPressed = true
            HapticService.play(.click)
            Task {
              try? await Task.sleep(nanoseconds: flashDuration)
              await MainActor.run {
                showPressed = false
              }
            }
          }
        }
      }
  }

  /// High-priority swipe gesture for page navigation
  private var swipeGesture: some Gesture {
    DragGesture(minimumDistance: 30)
      .onEnded { value in
        // Only handle horizontal swipes
        let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
        guard isHorizontal else { return }

        // Mark that we swiped (to suppress flash on release)
        didSwipe = true

        if value.translation.width < -30 {
          onSwipeLeft?()   // Swipe left = go to next page
        } else if value.translation.width > 30 {
          onSwipeRight?()  // Swipe right = go to previous page
        }
      }
  }
}

// MARK: - Convenience Extension

extension ButtonStyle where Self == SwipeAwareButtonStyle {
  /// Button style that delays pressed state and allows swipes for page navigation.
  static var swipeAware: SwipeAwareButtonStyle { SwipeAwareButtonStyle() }
}
