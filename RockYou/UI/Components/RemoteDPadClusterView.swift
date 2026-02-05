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

  @ObservedObject private var domeManager = DomeAnimationManager.shared
  @State private var showDomeMenu = false

  var body: some View {
    VStack(spacing: topRowToDPadSpacing * scaleFactor) {
      HStack(spacing: RemoteCoreButtonMetrics.topKeyHorizontalPadding * scaleFactor) {
        TopKeyButton(
          systemName: "asterisk",
          width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor,
          height: RemoteCoreButtonMetrics.topKeyHeight * scaleFactor,
          baseColor: rokuDarkPurple
        ) { onAction(.options) }

        Color.clear
          .frame(width: RemoteCoreButtonMetrics.topKeyWidth * scaleFactor)
          .contentShape(Rectangle())
          .onLongPressGesture(minimumDuration: 0.35) {
            showDomeMenu = true
          }
          .popover(isPresented: $showDomeMenu, attachmentAnchor: .rect(.bounds)) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Breaker Finish Animation")
                .font(.caption)
                .foregroundStyle(.secondary)
              ForEach(DomeAnimationFactory.presets, id: \.name) { preset in
                Button(preset.name) {
                  triggerDomeAnimation(named: preset.name)
                  showDomeMenu = false
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
              }
            }
            .padding(10)
            .frame(minWidth: 200)
            .presentationCompactAdaptation(.popover)
          }

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

  private func triggerDomeAnimation(named name: String) {
    domeManager.setNextPresetName(name)
    let dpadSize = 210 * scaleFactor
    let domeSize = dpadSize * CGFloat(DomeSceneConfig.renderCanvasScale)
    domeManager.start(referenceDomeSize: domeSize)
  }
}
