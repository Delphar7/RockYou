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

      TopKeyButton(
        systemName: "house.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) {}
      .sweepable(
        icon: "house.fill",
        color: .indigo,
        delay: phoneHomeDelay ?? 0,
        tooltip: "Hold to go home",
        onSweepComplete: { onAction(.home) }
      )

      TopKeyButton(
        systemName: "gearshape.fill",
        width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
        height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor
      ) { showingConfigure = true }
    }
    .padding(.top, 0)
  }
}
