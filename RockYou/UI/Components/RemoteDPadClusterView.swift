import SwiftUI

struct RemoteDPadClusterView: View {
  let scaleFactor: CGFloat
  let onAction: (RemoteAction) -> Void

  var body: some View {
    VStack(spacing: 8 * scaleFactor) {
      HStack(spacing: 32 * scaleFactor) {
        TopKeyButton(
          systemName: "asterisk",
          width: 72 * scaleFactor,
          height: 54 * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.options) }
        Spacer().frame(width: 72 * scaleFactor)
        TopKeyButton(
          systemName: "gobackward.15",
          width: 72 * scaleFactor,
          height: 54 * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.instantReplay) }
      }

      DPadView(
        onDirection: { onAction($0) },
        onOK: { onAction(.ok) },
        size: 150 * scaleFactor
      )
    }
    .padding(.vertical, 12 * scaleFactor)
  }
}
