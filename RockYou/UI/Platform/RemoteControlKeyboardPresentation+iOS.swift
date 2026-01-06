import SwiftUI

extension View {
  /// iOS keyboard presentation: wraps content in a ScrollView with safeAreaInset for KeyboardInputBar.
  @ViewBuilder
  func platformKeyboardScrollWrapper(
    containerSize: CGSize,
    showingKeyboard: Bool,
    target: RemoteControlView.KeyboardTarget?,
    onDismiss: @escaping () -> Void
  ) -> some View {
    ScrollView(.vertical, showsIndicators: false) {
      self
        .frame(width: containerSize.width, height: containerSize.height)
    }
    .scrollDisabled(!showingKeyboard)
    .safeAreaInset(edge: .bottom) {
      if showingKeyboard, let target {
        KeyboardInputBar(target: target, onDismiss: onDismiss)
      }
    }
  }

  /// iOS: keyboard is presented via safeAreaInset, not a sheet. This is a no-op.
  func platformKeyboardSheet(
    isPresented: Binding<Bool>,
    target: @escaping () -> RemoteControlView.KeyboardTarget?
  ) -> some View {
    let _ = (isPresented, target)
    return self
  }
}
