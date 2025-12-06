import SwiftUI

struct RemoteControlViewHost: View {
  @Environment(\.controlActiveState) private var controlActiveState

  let onAction: (RemoteAction) -> Void

  var body: some View {
    let windowIsActive = controlActiveState != .inactive
    return RemoteControlView(onAction: onAction, windowIsActive: windowIsActive)
  }
}
