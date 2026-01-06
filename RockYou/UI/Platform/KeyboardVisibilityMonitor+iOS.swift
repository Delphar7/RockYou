//
//  KeyboardVisibilityMonitor+iOS.swift
//  RockYou
//
//  Observes iOS keyboard show/hide notifications and exposes height for layout.
//

#if os(iOS)
import Combine
import UIKit

/// Observable object that tracks iOS software keyboard visibility and height.
@MainActor
final class KeyboardVisibilityMonitor: ObservableObject {
  static let shared = KeyboardVisibilityMonitor()

  @Published private(set) var isVisible: Bool = false
  @Published private(set) var height: CGFloat = 0

  private var cancellables = Set<AnyCancellable>()

  private init() {
    NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        self?.handleKeyboardWillShow(notification)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleKeyboardWillHide()
      }
      .store(in: &cancellables)
  }

  private func handleKeyboardWillShow(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
      return
    }
    height = frame.height
    isVisible = true
  }

  private func handleKeyboardWillHide() {
    isVisible = false
    height = 0
  }
}
#endif
