//
//  CompactDelayPicker+macOS.swift
//  RockYou (Shared)
//

  import SwiftUI

  struct CompactDelayPicker: View {
    @Binding var selection: TimeInterval?
    var alignment: Alignment = .trailing
    let targetHeight: CGFloat

    var body: some View {
      Picker("", selection: $selection) {
        ForEach(Array(SweeperDelayOptions.options.enumerated()), id: \.offset) { _, delay in
          Text(SweeperDelayOptions.label(for: delay))
            .tag(delay)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .controlSize(.small)
      .frame(maxWidth: .infinity, alignment: alignment)
      .frame(height: targetHeight)
    }
  }
