import SwiftUI

struct RemoteControlsSectionView: View {
  let scaleFactor: CGFloat
  let layoutMode: LayoutMode
  let selectedTVName: String?
  let selectedStreamerName: String?
  let selectedDeviceId: String?
  let hardwareControlsAvailable: Bool
  @Binding var showingConfigure: Bool
  @Binding var showingTVSelector: Bool
  let phonePowerDelay: TimeInterval?
  let phoneHomeDelay: TimeInterval?
  let onAction: (RemoteAction) -> Void

  // Measured (unscaled) size of the purple control cluster.
  @State private var controlClusterNaturalSize: CGSize = .zero

  private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
      let next = nextValue()
      // Prefer a non-zero measurement.
      if next != .zero { value = next }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      RemoteTopBarView(
        scaleFactor: scaleFactor,
        selectedTVName: selectedTVName,
        selectedStreamerName: selectedStreamerName,
        selectedDeviceId: selectedDeviceId,
        hardwareControlsAvailable: hardwareControlsAvailable,
        showingTVSelector: $showingTVSelector,
        phonePowerDelay: phonePowerDelay,
        onAction: onAction
      )

      GeometryReader { proxy in
          let available = proxy.size
          let natural = controlClusterNaturalSize
        let targetFraction = RemoteControlsSectionPlatform.targetFraction(layoutMode: layoutMode)
        let targetW = available.width * targetFraction
        let targetH = available.height * targetFraction

        // Choose the uniform scale that ensures the cluster fits within 80% of BOTH
        // available width and height (never cramping either dimension).
        let scaleW: CGFloat = (natural.width > 0) ? (targetW / natural.width) : 1.0
          let scaleH: CGFloat = (natural.height > 0) ? (targetH / natural.height) : 1.0
        // Allow scaling UP or DOWN. (Previous clamp to <= 1.0 prevented any visible change
        // when the cluster was already smaller than the target.)
        let scale: CGFloat = max(0.01, min(scaleW, scaleH))

        VStack(spacing: 0) {
          controlCluster
            // Measure natural (unscaled) size.
              .background(
                GeometryReader { inner in
                  Color.clear.preference(key: SizePreferenceKey.self, value: inner.size)
                }
            )
            .scaleEffect(scale, anchor: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .onPreferenceChange(SizePreferenceKey.self) { newSize in
          // Avoid churn on zero/invalid sizes.
          if newSize != .zero, newSize != controlClusterNaturalSize {
            controlClusterNaturalSize = newSize
          }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var controlCluster: some View {
    VStack(spacing: 0) {
      RemoteNavRowView(
        scaleFactor: scaleFactor,
        phoneHomeDelay: phoneHomeDelay,
        showingConfigure: $showingConfigure,
        onAction: onAction
      ).padding(.bottom, 6 * scaleFactor)

      RemoteDPadClusterView(scaleFactor: scaleFactor, onAction: onAction)
        .padding(.bottom, 10 * scaleFactor)

      RemoteTransportControlsView(scaleFactor: scaleFactor, onAction: onAction)
        .padding(.bottom, 8 * scaleFactor)

      RemoteVolumeControlsView(
        scaleFactor: scaleFactor,
        hardwareControlsAvailable: hardwareControlsAvailable,
        onAction: onAction
      ).padding(.bottom, 10 * scaleFactor)
    }
  }
}
