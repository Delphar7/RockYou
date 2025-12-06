import SwiftUI

struct RemoteTransportControlsView: View {
  let scaleFactor: CGFloat
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: 29 * scaleFactor) {
      CircleKeyButton(systemName: "backward.fill", size: 72 * scaleFactor, baseColor: rokuDarkPurple) { onAction(.rewind) }
      CircleKeyButton(systemName: "playpause.fill", size: 84 * scaleFactor, baseColor: rokuDarkPurple) { onAction(.playPause) }
      CircleKeyButton(systemName: "forward.fill", size: 72 * scaleFactor, baseColor: rokuDarkPurple) { onAction(.forward) }
    }
    .padding(.top, 8 * scaleFactor)
  }
}
