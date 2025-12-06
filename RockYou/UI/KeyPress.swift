import SwiftUI
extension View {
  func remoteControlKeyPresses(onAction: @escaping (RemoteAction) -> Void) -> some View {
    self
      .onKeyPress(.home) {
        onAction(.home)
        return .handled
      }
      .onKeyPress(.escape) {
        onAction(.back)
        return .handled
      }
      .onKeyPress(.upArrow) {
        onAction(.up)
        return .handled
      }
      .onKeyPress(.downArrow) {
        onAction(.down)
        return .handled
      }
      .onKeyPress(.leftArrow) {
        onAction(.left)
        return .handled
      }
      .onKeyPress(.rightArrow) {
        onAction(.right)
        return .handled
      }
      .onKeyPress(.return) {
        onAction(.ok)
        return .handled
      }
      .onKeyPress(.space) {
        onAction(.playPause)
        return .handled
      }
      .onKeyPress("+") {
        onAction(.volumeUp)
        return .handled
      }
      .onKeyPress("-") {
        onAction(.volumeDown)
        return .handled
      }
  }
}
