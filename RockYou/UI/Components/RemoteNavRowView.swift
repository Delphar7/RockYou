import SwiftUI

struct RemoteNavRowView: View {
  let scaleFactor: CGFloat
  let phoneHomeDelay: TimeInterval?
  @Binding var showingConfigure: Bool
  let onAction: (RemoteAction) -> Void

  var body: some View {
    HStack(spacing: 32 * scaleFactor) {
      TopKeyButton(systemName: "chevron.left", width: 72 * scaleFactor, height: 54 * scaleFactor) { onAction(.back) }

      if let phoneHomeDelay, phoneHomeDelay > 0 {
        TopKeyButton(systemName: "house.fill", width: 72 * scaleFactor, height: 54 * scaleFactor) { }
          .sweepable(
            icon: "house.fill",
            color: .indigo,
            delay: phoneHomeDelay,
            tooltip: "Hold to go home",
            onSweepComplete: { onAction(.home) }
          )
      } else {
        TopKeyButton(systemName: "house.fill", width: 72 * scaleFactor, height: 54 * scaleFactor) { onAction(.home) }
      }

      TopKeyButton(systemName: "gearshape.fill", width: 72 * scaleFactor, height: 54 * scaleFactor) { showingConfigure = true }
    }
    .padding(.top, 6 * scaleFactor)
  }
}
