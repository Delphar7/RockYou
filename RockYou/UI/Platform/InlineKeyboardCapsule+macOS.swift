import SwiftUI

/// macOS inline keyboard entry capsule that slides out from the keyboard button.
struct InlineKeyboardCapsule: View {
  let target: RemoteControlView.KeyboardTarget
  let scaleFactor: CGFloat
  var leadingInset: CGFloat = 0  // Extra leading padding so text clears the overlapping button

  @State private var text: String = ""
  @State private var lastSentText: String = ""
  @FocusState private var isFocused: Bool
  @State private var isPrimed = false

  private var capsuleHeight: CGFloat { 48 * scaleFactor }

  private var liveTextEditStatus: RokuTextEditStatus {
    RokuTextEditStateManager.shared.status(for: target.targetDevice.id)
  }

  private var liveTexteditId: String? {
    liveTextEditStatus.texteditId
  }

  var body: some View {
    TextField("Type…", text: $text)
      .textFieldStyle(.plain)
      .font(.system(size: max(12, 16 * scaleFactor)))
      .foregroundStyle(.white)
      .focused($isFocused)
      .onChange(of: text) { oldValue, newValue in
        guard isPrimed else { return }
        handleTextChange(from: oldValue, to: newValue)
      }
      .padding(.leading, leadingInset + 16)
      .padding(.trailing, 16)
      .frame(height: capsuleHeight)
      .background(
        Capsule()
          .fill(.ultraThinMaterial)
          .opacity(0.95)
          .environment(\.colorScheme, .dark)
      )
      .overlay(
        Capsule()
          .strokeBorder(rokuPurple, lineWidth: 2)
      )
      .task {
        // Prime from Roku textedit state if available
        await primeFromTexteditIfAvailable()
        lastSentText = text
        isPrimed = true
        isFocused = true
      }
  }

  // MARK: - Text Sync with Roku

  private func handleTextChange(from oldValue: String, to newValue: String) {
    guard newValue != lastSentText else { return }
    lastSentText = newValue

    Task {
      // Prefer full-text updates when Roku reports an active text field.
      if let id = liveTexteditId {
        _ = await RokuECPClient.shared.setTexteditText(
          texteditId: id,
          text: newValue,
          for: target.targetDevice
        )
      } else {
        // Fallback to keystroke-based entry if no textedit ID
        await sendKeystrokeDelta(from: oldValue, to: newValue)
      }
    }
  }

  private func sendKeystrokeDelta(from oldValue: String, to newValue: String) async {
    // Simple: if text was added, send the new characters as keystrokes
    if newValue.hasPrefix(oldValue) {
      let added = String(newValue.dropFirst(oldValue.count))
      for char in added {
        let charStr = String(char)
        let encoded =
          charStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? charStr
        _ = await RokuECPClient.shared.sendKeypress("Lit_\(encoded)", to: target.targetDevice)
      }
    } else if oldValue.hasPrefix(newValue) {
      // Characters were deleted - send backspaces
      let deleteCount = oldValue.count - newValue.count
      for _ in 0..<deleteCount {
        _ = await RokuECPClient.shared.sendKeypress("Backspace", to: target.targetDevice)
      }
    } else {
      // Complex edit - clear and re-type (not ideal, but functional)
      for _ in 0..<oldValue.count {
        _ = await RokuECPClient.shared.sendKeypress("Backspace", to: target.targetDevice)
      }
      for char in newValue {
        let charStr = String(char)
        let encoded =
          charStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? charStr
        _ = await RokuECPClient.shared.sendKeypress("Lit_\(encoded)", to: target.targetDevice)
      }
    }
  }

  private func primeFromTexteditIfAvailable() async {
    guard let state = await RokuECPClient.shared.queryTexteditState(for: target.targetDevice)
    else {
      return
    }
    await MainActor.run {
      text = state.text
    }
  }
}
