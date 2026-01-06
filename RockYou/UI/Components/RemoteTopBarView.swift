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

  // macOS inline keyboard support (defaults for legacy call sites)
  var layoutMode: LayoutMode = .portraitCompact
  var keyboardTarget: RemoteControlView.KeyboardTarget? = nil

  private var keyboardGlyphSize: CGFloat {
    // Keep the glyph proportional to the button height as we scale the header.
    // (Previously the frame scaled but the SF Symbol stayed at a fixed point size.)
    max(12, AppFontSize.veryLarge * scaleFactor)
  }

  private var keyboardButtonWidth: CGFloat { 68 * scaleFactor }
  private var powerButtonWidth: CGFloat { 68 * scaleFactor }
  private var buttonHeight: CGFloat { 48 * scaleFactor }

  var body: some View {
    ZStack {
      // Device selector in center
      deviceSelectorBar

      HStack(alignment: .top, spacing: 8) {
        // Keyboard button is always visible

        ZStack(alignment: .leading) {
          #if os(macOS)
            // Inline capsule slides out like a drawer from behind the keyboard button
            if let target = keyboardTarget {
              InlineKeyboardCapsule(
                target: target,
                scaleFactor: scaleFactor,
                leadingInset: keyboardButtonWidth  // Extra padding so text clears the button
              )
              .offset(y: buttonHeight * 0.12)  // 1/8 down the button so it doesn't show on button press
              .padding(.top, 8)
              .scaleEffect(x: isKeyboardShown ? 1 : 0.001, y: 1, anchor: .leading)
              .opacity(isKeyboardShown ? 1 : 0)
            }
          #endif
          keyboardButton
        }
        Spacer(minLength: 16)

        if showsPowerButton {
          SafePowerButton(
            onPower: { onAction(.power) },
            style: .custom(height: buttonHeight, showLabel: false),
            safetyDelay: phonePowerDelay
          )
          .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
          .frame(width: powerButtonWidth)
          .padding(.top, 8)
        }
      }
      .padding(.horizontal, edgePadding)
      .animation(.easeInOut(duration: 0.25), value: isKeyboardShown)
    }
  }

  private var deviceSelectorBar: some View {
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
  }

  private var keyboardButton: some View {
    Button {
      onKeyboard()
    } label: {
      Image(systemName: isKeyboardShown ? "keyboard.chevron.compact.down" : "keyboard")
        .font(.system(size: keyboardGlyphSize, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: keyboardButtonWidth, height: buttonHeight)
    }
    .buttonStyle(
      MaterialButtonEffect.CapsuleStyle(baseColor: rokuPurple, seed: Self.helpMaterialSeed)
    )
    .padding(.top, 8)
  }
}
