// EngineConfigPanel.swift
// RockYou
//
// Auto-generates SwiftUI controls from PropertyConfig arrays.
// macOS-only (excluded from iOS via build settings)
//
// Usage:
// ```swift
// @Observable
// final class MyEngine {
//   var speed: Double = 1.0
//   var enabled: Bool = true
//
//   static let config: [PropertyConfig<MyEngine>] = [
//     .slider(\.speed, "Speed", 0...10, step: 0.1),
//     .toggle(\.enabled, "Enabled"),
//   ]
// }
//
// struct MyView: View {
//   @State private var engine = MyEngine()
//
//   var body: some View {
//     HSplitView {
//       MyCanvas(engine: engine)
//       ConfigPanel(engine: engine, config: MyEngine.config)
//     }
//   }
// }
// ```

import SwiftUI

/// Auto-generates a config panel from PropertyConfig array
struct ConfigPanel<E: AnyObject & Observable>: View {
  var engine: E
  var config: [PropertyConfig<E>]
  var width: CGFloat = 280

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(config.enumerated()), id: \.offset) { _, prop in
          propertyControl(prop)
        }
      }
      .padding()
    }
    .frame(width: width)
  }

  @ViewBuilder
  private func propertyControl(_ prop: PropertyConfig<E>) -> some View {
    switch prop.control {
    case .slider(let min, let max, let step):
      sliderControl(prop: prop, min: min, max: max, step: step)

    case .toggle:
      toggleControl(prop: prop)

    case .stepper(let min, let max, let step):
      stepperControl(prop: prop, min: min, max: max, step: step)

    case .picker(let options, let fromIndex, let toIndex):
      pickerControl(prop: prop, options: options, fromIndex: fromIndex, toIndex: toIndex)

    case .text:
      textControl(prop: prop)

    case .color:
      colorControl(prop: prop)
    }
  }

  // MARK: - Slider

  @ViewBuilder
  private func sliderControl(prop: PropertyConfig<E>, min: Double, max: Double, step: Double) -> some View {
    let currentValue = (prop.getValue(engine) as? Double) ?? 0
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(prop.name)
        Spacer()
        Text(String(format: "%.3f", currentValue))
          .foregroundColor(.secondary)
          .monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { (prop.getValue(engine) as? Double) ?? 0 },
          set: { prop.setValue(engine, $0) }
        ),
        in: min...max,
        step: step
      )
    }
  }

  // MARK: - Toggle

  @ViewBuilder
  private func toggleControl(prop: PropertyConfig<E>) -> some View {
    Toggle(
      prop.name,
      isOn: Binding(
        get: { (prop.getValue(engine) as? Bool) ?? false },
        set: { prop.setValue(engine, $0) }
      )
    )
  }

  // MARK: - Stepper

  @ViewBuilder
  private func stepperControl(prop: PropertyConfig<E>, min: Int, max: Int, step: Int) -> some View {
    let currentValue = (prop.getValue(engine) as? Int) ?? 0
    HStack {
      Text(prop.name)
      Spacer()
      Text("\(currentValue)")
        .foregroundColor(.secondary)
        .monospacedDigit()
        .frame(width: 40, alignment: .trailing)
      Stepper(
        "",
        value: Binding(
          get: { (prop.getValue(engine) as? Int) ?? 0 },
          set: { prop.setValue(engine, $0) }
        ),
        in: min...max,
        step: step
      )
      .labelsHidden()
    }
  }

  // MARK: - Picker

  @ViewBuilder
  private func pickerControl(
    prop: PropertyConfig<E>,
    options: [String],
    fromIndex: @escaping (Int) -> Any,
    toIndex: @escaping (Any) -> Int
  ) -> some View {
    HStack {
      Text(prop.name)
      Spacer()
      Picker(
        "",
        selection: Binding(
          get: { toIndex(prop.getValue(engine)) },
          set: { prop.setValue(engine, fromIndex($0)) }
        )
      ) {
        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
          Text(option).tag(index)
        }
      }
      .labelsHidden()
      .frame(width: 120)
    }
  }

  // MARK: - Text

  @ViewBuilder
  private func textControl(prop: PropertyConfig<E>) -> some View {
    HStack {
      Text(prop.name)
      Spacer()
      // Handle both String and Int
      if prop.getValue(engine) is Int {
        let intValue = (prop.getValue(engine) as? Int) ?? 0
        TextField(
          "",
          value: Binding(
            get: { (prop.getValue(engine) as? Int) ?? 0 },
            set: { prop.setValue(engine, $0) }
          ),
          format: .number
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 100)
        .multilineTextAlignment(.trailing)
      } else {
        TextField(
          "",
          text: Binding(
            get: { (prop.getValue(engine) as? String) ?? "" },
            set: { prop.setValue(engine, $0) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 150)
      }
    }
  }

  // MARK: - Color

  @ViewBuilder
  private func colorControl(prop: PropertyConfig<E>) -> some View {
    HStack {
      Text(prop.name)
      Spacer()
      ColorPicker(
        "",
        selection: Binding(
          get: { (prop.getValue(engine) as? Color) ?? .white },
          set: { prop.setValue(engine, $0) }
        )
      )
      .labelsHidden()
    }
  }
}

// MARK: - Preview

#Preview("Config Panel Demo") {
  Text("See ConfigPanel usage in debug views")
    .padding()
}
