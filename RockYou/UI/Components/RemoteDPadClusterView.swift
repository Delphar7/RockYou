import SwiftUI

struct RemoteDPadClusterView: View {
  let scaleFactor: CGFloat
  let onAction: (RemoteAction) -> Void

  var body: some View {
    VStack(spacing: 8 * scaleFactor) {
      HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor) {
        TopKeyButton(
          systemName: "asterisk",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.options) }
        Spacer().frame(width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor)
        TopKeyButton(
          systemName: "gobackward.15",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.instantReplay) }
      }

      DPadView(
        onDirection: { onAction($0) },
        onOK: { onAction(.ok) },
        size: 210 * scaleFactor
      )
    }
    .padding(.vertical, RemoteCoreButtonMetrics.topKeyVerticalPadding * scaleFactor)
  }
}
