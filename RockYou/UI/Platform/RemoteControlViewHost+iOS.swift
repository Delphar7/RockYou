import SwiftUI

struct RemoteControlViewHost: View {
  let onAction: (RemoteAction) -> Void

  var body: some View {
    RemoteControlView(onAction: onAction, windowIsActive: RemoteControlPlatform.windowIsActiveDefault)
  }
}
