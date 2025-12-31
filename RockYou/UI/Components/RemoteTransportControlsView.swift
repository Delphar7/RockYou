import SwiftUI

struct RemoteTransportControlsView: View {
  let scaleFactor: CGFloat
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: RemoteCoreButtonMetrics.circleKeyHorizontalSpacing * scaleFactor) {
      CircleKeyButton(
        systemName: "backward.fill",
        size: RemoteCoreButtonMetrics.circleKeySize * scaleFactor,
        baseColor: rokuDarkPurple
      ) { onAction(.rewind) }
      CircleKeyButton(
        systemName: "playpause.fill",
        size: RemoteCoreButtonMetrics.circleKeyLargeSize * scaleFactor,
        baseColor: rokuDarkPurple
      ) { onAction(.playPause) }
      CircleKeyButton(
        systemName: "forward.fill",
        size: RemoteCoreButtonMetrics.circleKeySize * scaleFactor,
        baseColor: rokuDarkPurple
      ) { onAction(.forward) }
    }
    .padding(.top, RemoteCoreButtonMetrics.circleKeyVerticalPadding * scaleFactor)
  }
}
