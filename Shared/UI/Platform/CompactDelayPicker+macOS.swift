//
//  CompactDelayPicker+macOS.swift
//  RockYou (Shared)
//

  import SwiftUI

  struct CompactDelayPicker: View {
    @Binding var selection: TimeInterval?
    var alignment: Alignment = .trailing
    let targetHeight: CGFloat
  var options: [TimeInterval?] = SweeperDelayOptions.options
  var labelFormatter: (TimeInterval?) -> String = SweeperDelayOptions.label(for:)

    var body: some View {
      Picker("", selection: $selection) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, value in
        Text(labelFormatter(value))
          .tag(value)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .controlSize(.small)
      .frame(maxWidth: .infinity, alignment: alignment)
      .frame(height: targetHeight)
    }
  }
