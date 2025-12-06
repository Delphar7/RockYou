//
//  CompactDelayPicker+iOS.swift
//  RockYou (Shared)
//

  import SwiftUI

  struct CompactDelayPicker: View {
    @Binding var selection: TimeInterval?
    var alignment: Alignment = .trailing
    let targetHeight: CGFloat

    var body: some View {
      let wheelScaleY: CGFloat = 0.82

      Picker("", selection: $selection) {
        ForEach(Array(SweeperDelayOptions.options.enumerated()), id: \.offset) { _, delay in
          Text(SweeperDelayOptions.label(for: delay))
            .font(.system(size: 15))
            .tag(delay)
        }
      }
      .pickerStyle(.wheel)
      .labelsHidden()
      .frame(maxWidth: .infinity, alignment: alignment)
      .frame(height: targetHeight / wheelScaleY)
      .scaleEffect(x: 1, y: wheelScaleY, anchor: .center)
      .frame(height: targetHeight)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
