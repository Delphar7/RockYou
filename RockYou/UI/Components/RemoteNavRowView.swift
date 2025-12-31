import SwiftUI

struct RemoteNavRowView: View {
  let scaleFactor: CGFloat
  let phoneHomeDelay: TimeInterval?
  @Binding var showingConfigure: Bool
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor) {
      TopKeyButton(
        systemName: "chevron.left",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { onAction(.back) }

      if let phoneHomeDelay, phoneHomeDelay > 0 {
        TopKeyButton(
          systemName: "house.fill",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
        ) {}
        .sweepable(
            icon: "house.fill",
            color: .indigo,
            delay: phoneHomeDelay,
            tooltip: "Hold to go home",
            onSweepComplete: { onAction(.home) }
          )
      } else {
        TopKeyButton(
          systemName: "house.fill",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
        ) { onAction(.home) }
      }

      TopKeyButton(
        systemName: "gearshape.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { showingConfigure = true }
    }
    .padding(.top, 0)
  }
}
