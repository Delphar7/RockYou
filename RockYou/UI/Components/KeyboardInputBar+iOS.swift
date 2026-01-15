//
//  KeyboardInputBar+iOS.swift
//  RockYou
//
//  Capsule-styled text input bar that attaches above the iOS keyboard.
//  Uses ECP-2 set-textedit-text for efficient text sync with Roku.
//

  import SwiftUI

  /// Floating capsule text input bar for iOS keyboard integration.
  @MainActor
  struct KeyboardInputBar: View {
    let target: RemoteControlView.KeyboardTarget?
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    @State private var text: String = ""
    @State private var lastSentText: String = ""
    @State private var isPrimed: Bool = false
    @State private var lastObservedTexteditId: String? = nil
    @State private var isApplyingRemoteText: Bool = false

    private var liveTextEditStatus: RokuTextEditStatus {
      RokuTextEditStateManager.shared.status(for: target?.targetDevice.id)
    }

    private var liveTexteditId: String? {
      liveTextEditStatus.texteditId
    }

    var body: some View {
      HStack(spacing: 12) {
        TextField("Type…", text: $text)
          .textFieldStyle(.plain)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(
            Capsule()
              .fill(Color.white.opacity(0.15))
          )
          .focused($isFocused)
          .submitLabel(.done)
          .onSubmit {
            Task { await sendSpecialKey("Enter") }
          }

        Button {
          onDismiss()
        } label: {
          Image(systemName: "keyboard.chevron.compact.down")
            .font(.system(size: AppFontSize.larger, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
      }
      .padding(.leading, 8)
      .padding(.trailing, 16)
      .padding(.vertical, 4)
      .contentShape(Rectangle())
      .sweepBlockingZone()  // Prevent sweepable gestures from passing through
      .background(
        Rectangle()
          .fill(.ultraThinMaterial)
          .ignoresSafeArea(edges: .bottom)
      )
      .onAppear {
        guard !isPrimed else { return }
        isPrimed = true
        lastObservedTexteditId = liveTexteditId

        // Delay focus request slightly to ensure view is in hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          isFocused = true
          Log.debug("Keyboard", "KeyboardInputBar requesting focus")
        }

        // Prime from Roku's current text
        Task {
          await primeFromTexteditIfAvailable()
          lastSentText = text
        }
      }
      .onChange(of: liveTextEditStatus.isActive) { _, isActive in
        // Auto-dismiss if Roku closes the text field
        if !isActive {
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !liveTextEditStatus.isActive {
              onDismiss()
            }
          }
        }
      }
      .onChange(of: liveTexteditId) { _, newId in
        // Re-prime when Roku focus changes to a different text field
        guard isPrimed, newId != lastObservedTexteditId else { return }
        lastObservedTexteditId = newId
        Task {
          await primeFromTexteditIfAvailable(forceAdopt: true)
          lastSentText = text
        }
      }
      .onChange(of: liveTextEditStatus.text) { _, newRemoteText in
        // Adopt remote edits without echoing
        guard isPrimed, let remote = newRemoteText, remote != text, remote != lastSentText else {
          return
        }
        isApplyingRemoteText = true
        text = remote
        lastSentText = remote
        isApplyingRemoteText = false
      }
      .onChange(of: text) { _, newValue in
        guard isPrimed, !isApplyingRemoteText, newValue != lastSentText else { return }
        Task { await sendTextChange(from: lastSentText, to: newValue) }
      }
    }

    // MARK: - ECP-2 Integration

    private func primeFromTexteditIfAvailable(forceAdopt: Bool = false) async {
      guard let target else { return }
      if let state = await RokuECPClient.shared.queryTexteditState(for: target.targetDevice) {
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

      // Prefer full-text updates when Roku reports an active text field
      if let id = liveTexteditId {
        let ok = await RokuECPClient.shared.setTexteditText(
          texteditId: id,
          text: new,
          for: target.targetDevice
        )
        if ok { lastSentText = new }
        return
      }

      // Fallback: incremental keypresses
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

    private func sendAsKeypressDiff(
      from old: String, to new: String, target: RemoteControlView.KeyboardTarget
    ) async {
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

      if !old.isEmpty { await sendBackspaces(old.count, target: target) }
      await sendLiteralString(new, target: target)
    }

    private func sendBackspaces(_ n: Int, target: RemoteControlView.KeyboardTarget) async {
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
        let lit = ecpLitKey(String(ch))
        _ = await RokuECPClient.shared.sendKeypressInSilo(
          lit,
          siloId: target.siloId,
          requiredDevices: target.requiredDevices,
          targetDevice: target.targetDevice
        )
      }
    }

    private func ecpLitKey(_ character: String) -> String {
      let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
      let encoded = character.addingPercentEncoding(withAllowedCharacters: allowed) ?? character
      return "Lit_\(encoded)"
  }
}
