import SwiftUI

struct RemoteTopBarView: View {
  private static let helpMaterialSeed: UInt64 = 0xC0FFEE

  let scaleFactor: CGFloat
  var edgePadding: CGFloat = RemoteControlPlatform.remoteTopBarEdgePadding
  let selectedTVName: String?
  let selectedStreamerName: String?
  let selectedDeviceId: String?
  let hardwareControlsAvailable: Bool
  @Binding var showingTVSelector: Bool
  let isKeyboardShown: Bool
  let onKeyboard: () -> Void
  let phonePowerDelay: TimeInterval?
  var showsPowerButton: Bool = true
  let onAction: (RemoteAction) -> Void

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
          onKeyboard()
        } label: {
          Image(systemName: isKeyboardShown ? "keyboard.chevron.compact.down" : "keyboard")
            .font(.system(size: AppFontSize.veryLarge, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 68 * scaleFactor, height: 48 * scaleFactor)
        }
        .buttonStyle(
          MaterialButtonEffect.CapsuleStyle(baseColor: rokuPurple, seed: Self.helpMaterialSeed)
        )
        .padding(.top, 8)

        Spacer()
        if showsPowerButton {
          SafePowerButton(
            onPower: { onAction(.power) },
            style: .custom(height: 48 * scaleFactor, showLabel: false),
            safetyDelay: phonePowerDelay
          )
          .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
          .frame(width: 68 * scaleFactor)
          .padding(.top, 8)
        }
      }
      .padding(.horizontal, edgePadding)
    }
  }

}
