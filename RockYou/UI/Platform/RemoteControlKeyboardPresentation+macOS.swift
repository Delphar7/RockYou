import SwiftUI

extension View {
  /// macOS keyboard presentation: no ScrollView wrapper needed (sheet is handled separately).
  func platformKeyboardScrollWrapper(
    containerSize: CGSize,
    showingKeyboard: Bool,
    target: RemoteControlView.KeyboardTarget?,
    onDismiss: @escaping () -> Void
  ) -> some View {
    // macOS doesn't use the scrollable keyboard pattern - just return self unchanged.
    // The keyboard is presented via .sheet() at the top level.
    let _ = (containerSize, showingKeyboard, target, onDismiss)
    return self
  }

  /// macOS: keyboard is presented inline in the header bar, not as a sheet.
  func platformKeyboardSheet(
    isPresented: Binding<Bool>,
    target: @escaping () -> RemoteControlView.KeyboardTarget?
  ) -> some View {
    let _ = (isPresented, target)
    return self
  }
}
