import SwiftUI

struct RemoteTopBarView: View {
  private static let docsURL: URL = {
    guard let url = URL(string: "https://jtr.sh/RockYou/docs/") else {
      preconditionFailure("Invalid docs URL")
    }
    return url
  }()
  private static let helpMaterialSeed: UInt64 = 0xC0FFEE

  let scaleFactor: CGFloat
  var edgePadding: CGFloat = RemoteTopBarPlatform.edgePadding
  let selectedTVName: String?
  let selectedStreamerName: String?
  let selectedDeviceId: String?
  let hardwareControlsAvailable: Bool
  @Binding var showingTVSelector: Bool
  let phonePowerDelay: TimeInterval?
  let onAction: (RemoteAction) -> Void
  @State private var isPresentingHelp: Bool = false

  var body: some View {
    ZStack {
      TVSelectorBar(
        selectedTVName: selectedTVName,
        selectedStreamerName: selectedStreamerName,
        selectedDeviceId: selectedDeviceId,
        showingSelector: showingTVSelector,
        onTap: {
          withAnimation(.easeInOut(duration: 0.2)) {
            showingTVSelector.toggle()
          }
        }
      )

      HStack(alignment: .top) {
        Button {
          isPresentingHelp = true
        } label: {
          Image(systemName: "questionmark")
            .font(.system(size: AppFontSize.medium, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 68 * scaleFactor, height: 48 * scaleFactor)
        }
        .buttonStyle(
          MaterialButtonEffect.CapsuleStyle(baseColor: rokuPurple, seed: Self.helpMaterialSeed)
        )
        .padding(.top, 8)

        Spacer()
        SafePowerButton(
          onPower: { onAction(.power) },
          style: .custom(height: 48 * scaleFactor, showLabel: false),
          safetyDelay: phonePowerDelay
        )
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
        .frame(width: 68 * scaleFactor)
        .padding(.top, 8)
      }
      .padding(.horizontal, edgePadding)
    }
    .platformHelpPresentation(isPresented: $isPresentingHelp, url: Self.docsURL)
  }
}
