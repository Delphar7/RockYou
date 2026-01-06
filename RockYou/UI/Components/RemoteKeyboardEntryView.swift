import SwiftUI

/// Minimal OS-keyboard-backed text entry UI for Roku ECP-2.
///
/// - iOS/iPadOS: presented as a sheet; uses system keyboard.
/// - macOS: same view; uses a normal text field.
@MainActor
struct RemoteKeyboardEntryView: View {
  let target: RemoteControlView.KeyboardTarget?

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isFocused: Bool

  @State private var text: String = ""
  @State private var lastSentText: String = ""
  @State private var isPrimed: Bool = false
  @State private var lastObservedTexteditId: String? = nil
  @State private var isApplyingRemoteText: Bool = false
  @State private var didRequestInitialFocus: Bool = false
  @State private var pendingAutoDismissTask: Task<Void, Never>? = nil
  @State private var focusRetryTask: Task<Void, Never>? = nil
  @State private var isDismissingLocally: Bool = false

  private var liveTextEditStatus: RokuTextEditStatus {
    RokuTextEditStateManager.shared.status(for: target?.targetDevice.id)
  }

  // If Roku reports an active text field, we can drive it with `set-textedit-text` (better for paste/edit).
  private var liveTexteditId: String? {
    liveTextEditStatus.texteditId
  }

  var body: some View {
    bodyContent
#if !os(iOS)
    .presentationDetents([.height(180), .medium])
#endif
    .task {
      guard !isPrimed else { return }
      isPrimed = true
      requestFocusIfNeeded()

      // Best-effort: if Roku currently has a textedit field, start from its value.
      await primeFromTexteditIfAvailable()
      lastSentText = text
      lastObservedTexteditId = liveTexteditId
    }
    .onDisappear {
      focusRetryTask?.cancel()
      focusRetryTask = nil
      pendingAutoDismissTask?.cancel()
      pendingAutoDismissTask = nil
    }
    .onChange(of: liveTextEditStatus.isActive) { _, isActive in
      // If Roku closes the text field while we're open, follow it (parity with Roam auto-close).
      Log.debug(
        "Keyboard",
        "Textedit active=\(isActive ? "1" : "0") id=\(liveTexteditId ?? "nil")"
      )

      pendingAutoDismissTask?.cancel()
      pendingAutoDismissTask = nil

      guard !isActive else { return }
      // We have observed transient "off" moments during Roku textedit focus changes.
      // Debounce the auto-dismiss to avoid dropping iOS first-responder mid-transition
      // (which can leave the system keyboard in a weird partial state).
      pendingAutoDismissTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 300_000_000)
        if !liveTextEditStatus.isActive {
          Log.debug("Keyboard", "Auto-dismissing keyboard UI after debounce (textedit inactive)")
          done()
        }
      }
    }
    .onChange(of: liveTexteditId) { _, newId in
      // Critical for multi-textbox UIs: when Roku focus changes, the textedit id changes.
      // Re-prime so we don't keep sending edits to a stale text field.
      guard isPrimed else { return }
      if newId != lastObservedTexteditId {
        lastObservedTexteditId = newId
        Task {
          await primeFromTexteditIfAvailable(forceAdopt: true)
          lastSentText = text
        }
      }
    }
    .onChange(of: liveTextEditStatus.text) { _, newRemoteText in
      // If the official Roku app (or another controller) edits the same field,
      // adopt the remote text without echoing it back.
      guard isPrimed else { return }
      guard let remote = newRemoteText else { return }
      guard remote != text else { return }
      // If this is just our own echo, ignore.
      if remote == lastSentText { return }

      isApplyingRemoteText = true
      text = remote
      lastSentText = remote
      isApplyingRemoteText = false
    }
    .onChange(of: text) { _, newValue in
      // Avoid sending while initializing.
      guard isPrimed, !isApplyingRemoteText, newValue != lastSentText else { return }
      Task { await sendTextChange(from: lastSentText, to: newValue) }
    }
  }

  @ViewBuilder
  private var bodyContent: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Keyboard")
          .font(.system(size: AppFontSize.medium, weight: .semibold))
          .foregroundStyle(.white)
        Spacer()
        Button("Done") { done() }
          .buttonStyle(.borderedProminent)
      }

      TextField("Type…", text: $text)
        .textFieldStyle(.roundedBorder)
        .focused($isFocused)
        .submitLabel(.done)
        .onSubmit {
          Task { await sendSpecialKey("Enter") }
        }

      if DebugBuild.isEnabled {
        if target == nil {
          Text("Select a device to send keyboard input.")
            .font(.system(size: AppFontSize.body))
            .foregroundStyle(.white.opacity(AppOpacity.twoThirds))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let texteditId = liveTexteditId {
          Text("Text field active")
            .font(.system(size: AppFontSize.caption, weight: .medium))
            .foregroundStyle(.white.opacity(AppOpacity.twoThirds))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Text field active")
            .accessibilityValue(texteditId)
        } else {
          Text("Sending keypresses")
            .font(.system(size: AppFontSize.caption, weight: .medium))
            .foregroundStyle(.white.opacity(AppOpacity.twoThirds))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.black.opacity(AppOpacity.standard))
  }

  private func done() {
    dismissKeyboardUI(reason: "button")
  }

  private func dismissKeyboardUI(reason: String) {
    pendingAutoDismissTask?.cancel()
    pendingAutoDismissTask = nil
    focusRetryTask?.cancel()
    focusRetryTask = nil
    isFocused = false

    _ = reason
    dismiss()
  }

  private func requestFocusIfNeeded() {
    // Keep this simple for the "commit #1" baseline: request focus once when primed.
    // (We'll revisit focus strategies when we build the new iOS keyboard shell.)
    if didRequestInitialFocus { return }
    didRequestInitialFocus = true
    isFocused = true
  }

  private func primeFromTexteditIfAvailable(forceAdopt: Bool = false) async {
    guard let target else { return }
    if let state = await RokuECPClient.shared.queryTexteditState(for: target.targetDevice) {
      // Only adopt Roku's value if the user hasn't typed yet.
      if forceAdopt || text.isEmpty {
        text = state.text
      }
    }
  }

  private func sendTextChange(from old: String, to new: String) async {
    guard let target else {
      lastSentText = new
      return
    }

    // Prefer full-text updates when Roku reports an active text field.
    if let id = liveTexteditId {
      let ok = await RokuECPClient.shared.setTexteditText(
        texteditId: id,
        text: new,
        for: target.targetDevice
      )
      if ok {
        lastSentText = new
      }
      return
    }

    // Fallback: drive via incremental keypresses (works like the physical remote).
    await sendAsKeypressDiff(from: old, to: new, target: target)
    lastSentText = new
  }

  private func sendSpecialKey(_ key: String) async {
    guard let target else { return }
    _ = await RokuECPClient.shared.sendKeypressInSilo(
      key,
      siloId: target.siloId,
      requiredDevices: target.requiredDevices,
      targetDevice: target.targetDevice
    )
  }

  private func sendAsKeypressDiff(from old: String, to new: String, target: RemoteControlView.KeyboardTarget) async {
    // Simple and robust:
    // - If it's an append, send just the appended chars.
    // - If it's a pure delete-from-end, send Backspace N.
    // - Otherwise, "clear" by backspacing old.count, then type new.
    if new.hasPrefix(old) {
      let suffix = String(new.dropFirst(old.count))
      await sendLiteralString(suffix, target: target)
      return
    }

    if old.hasPrefix(new) {
      let n = old.count - new.count
      if n > 0 { await sendBackspaces(n, target: target) }
      return
    }

    // Fallback: attempt to clear then retype.
    if !old.isEmpty { await sendBackspaces(old.count, target: target) }
    await sendLiteralString(new, target: target)
  }

  private func sendBackspaces(_ n: Int, target: RemoteControlView.KeyboardTarget) async {
    guard n > 0 else { return }
    for _ in 0..<n {
      _ = await RokuECPClient.shared.sendKeypressInSilo(
        "Backspace",
        siloId: target.siloId,
        requiredDevices: target.requiredDevices,
        targetDevice: target.targetDevice
      )
    }
  }

  private func sendLiteralString(_ s: String, target: RemoteControlView.KeyboardTarget) async {
    for ch in s {
      let lit = Self.ecpLitKey(String(ch))
      _ = await RokuECPClient.shared.sendKeypressInSilo(
        lit,
        siloId: target.siloId,
        requiredDevices: target.requiredDevices,
        targetDevice: target.targetDevice
      )
    }
  }

  private static func ecpLitKey(_ character: String) -> String {
    // ECP convention: Lit_<printable> where <printable> may be percent-encoded UTF-8.
    // We percent-encode broadly to be safe across punctuation and non-ASCII.
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let encoded = character.addingPercentEncoding(withAllowedCharacters: allowed) ?? character
    return "Lit_\(encoded)"
  }
}
