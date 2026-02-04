import SwiftUI

struct RemoteDPadClusterView: View {
  let scaleFactor: CGFloat
  let onAction: (RemoteAction) -> Void
  /// Base (unscaled) spacing between the top key row (options/replay) and the DPad.
  /// Keeping this configurable allows experiment layouts to nudge the DPad without changing
  /// the DPad geometry itself.
  var topRowToDPadSpacing: CGFloat = 8
  /// When true, uses plain DPadView instead of LockableDPadView.
  /// This avoids RealityKit interference when used in hidden measurement probes.
  var forMeasurement: Bool = false

  var body: some View {
    VStack(spacing: topRowToDPadSpacing * scaleFactor) {
      HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor) {
        TopKeyButton(
          systemName: "asterisk",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.options) }

        Spacer()
          .frame(width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor)

        TopKeyButton(
          systemName: "gobackward.15",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.instantReplay) }
      }

      if forMeasurement {
        // Plain DPadView for measurement - avoids RealityKit in hidden probes
        DPadView(
          onDirection: { _ in },
          onOK: {},
          size: 210 * scaleFactor
        )
      } else {
        LockableDPadView(
          onDirection: { onAction($0) },
          onOK: { onAction(.ok) },
          size: 210 * scaleFactor
        )
      }
    }
    .padding(.vertical, RemoteCoreButtonMetrics.topKeyVerticalPadding * scaleFactor)
  }
}
