// EngineConfigPanel.swift
// RockYou
//
// Auto-generates SwiftUI controls from ConfigurableEngine property descriptors.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Auto-generates a config panel for any ConfigurableEngine.
///
/// Usage:
/// ```swift
/// struct MyExperimentDebugView: View {
///     @State private var engine = MyEngine()
///
///     var body: some View {
///         HSplitView {
///             MyEngineCanvas(engine: engine)
///             EngineConfigPanel(engine: engine)
///         }
///     }
/// }
/// ```
struct EngineConfigPanel<E: ConfigurableEngine & AnyObject & Observable>: View {
  var engine: E
  var width: CGFloat = 280

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(String(describing: type(of: engine)))
          .font(.headline)
          .padding(.bottom, 4)

        ForEach(E.propertyKeys, id: \.self) { key in
          if let descriptor = E.propertyDescriptors[key] {
            propertyControl(key: key, descriptor: descriptor)
          }
        }
      }
      .padding()
    }
    .frame(width: width)
  }

  @ViewBuilder
  private func propertyControl(key: String, descriptor: PropertyDescriptor) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      switch descriptor.control {
      case .auto:
        autoControl(key: key, descriptor: descriptor)

      case .slider(let min, let max, let step):
        sliderControl(key: key, name: descriptor.name, min: min, max: max, step: step)

      case .toggle:
        toggleControl(key: key, name: descriptor.name)

      case .intStepper(let min, let max, let step):
        intStepperControl(key: key, name: descriptor.name, min: min, max: max, step: step)

      case .picker(let options):
        pickerControl(key: key, name: descriptor.name, options: options)

      case .color:
        colorControl(key: key, name: descriptor.name)

      case .text:
        textControl(key: key, name: descriptor.name)
      }
    }
  }

  // MARK: - Auto Control (infer from type)

  @ViewBuilder
  private func autoControl(key: String, descriptor: PropertyDescriptor) -> some View {
    let value = engine.getValue(forKey: key)

    if value is Bool {
      toggleControl(key: key, name: descriptor.name)
    } else if value is Int {
      intStepperControl(key: key, name: descriptor.name, min: 0, max: 100, step: 1)
    } else if value is Double || value is Float || value is CGFloat {
      sliderControl(key: key, name: descriptor.name, min: 0, max: 1, step: 0.01)
    } else if value is String {
      textControl(key: key, name: descriptor.name)
    } else {
      Text("\(descriptor.name): \(String(describing: value))")
        .foregroundColor(.secondary)
    }
  }

  // MARK: - Slider (Double/Float/CGFloat)

  @ViewBuilder
  private func sliderControl(key: String, name: String, min: Double, max: Double, step: Double) -> some View {
    let currentValue = doubleValue(forKey: key)
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(name)
        Spacer()
        Text(String(format: "%.3f", currentValue))
          .foregroundColor(.secondary)
          .monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { doubleValue(forKey: key) },
          set: { engine.setValue($0, forKey: key) }
        ),
        in: min...max,
        step: step
      )
    }
  }

  private func doubleValue(forKey key: String) -> Double {
    switch engine.getValue(forKey: key) {
    case let v as Double: return v
    case let v as Float: return Double(v)
    case let v as CGFloat: return Double(v)
    default: return 0
    }
  }

  // MARK: - Toggle (Bool)

  @ViewBuilder
  private func toggleControl(key: String, name: String) -> some View {
    Toggle(
      name,
      isOn: Binding(
        get: { (engine.getValue(forKey: key) as? Bool) ?? false },
        set: { engine.setValue($0, forKey: key) }
      )
    )
  }

  // MARK: - Int Stepper

  @ViewBuilder
  private func intStepperControl(key: String, name: String, min: Int, max: Int, step: Int) -> some View {
    let currentValue = (engine.getValue(forKey: key) as? Int) ?? 0
    HStack {
      Text(name)
      Spacer()
      Text("\(currentValue)")
        .foregroundColor(.secondary)
        .monospacedDigit()
        .frame(width: 40, alignment: .trailing)
      Stepper(
        "",
        value: Binding(
          get: { (engine.getValue(forKey: key) as? Int) ?? 0 },
          set: { engine.setValue($0, forKey: key) }
        ),
        in: min...max,
        step: step
      )
      .labelsHidden()
    }
  }

  // MARK: - Picker (String enum)

  @ViewBuilder
  private func pickerControl(key: String, name: String, options: [String]) -> some View {
    let currentValue = (engine.getValue(forKey: key) as? String) ?? options.first ?? ""
    HStack {
      Text(name)
      Spacer()
      Picker(
        "",
        selection: Binding(
          get: { (engine.getValue(forKey: key) as? String) ?? options.first ?? "" },
          set: { engine.setValue($0, forKey: key) }
        )
      ) {
        ForEach(options, id: \.self) { option in
          Text(option).tag(option)
        }
      }
      .labelsHidden()
      .frame(width: 120)
    }
  }

  // MARK: - Color

  @ViewBuilder
  private func colorControl(key: String, name: String) -> some View {
    HStack {
      Text(name)
      Spacer()
      ColorPicker(
        "",
        selection: Binding(
          get: { (engine.getValue(forKey: key) as? Color) ?? .white },
          set: { engine.setValue($0, forKey: key) }
        )
      )
      .labelsHidden()
    }
  }

  // MARK: - Text

  @ViewBuilder
  private func textControl(key: String, name: String) -> some View {
    HStack {
      Text(name)
      Spacer()
      TextField(
        "",
        text: Binding(
          get: { (engine.getValue(forKey: key) as? String) ?? "" },
          set: { engine.setValue($0, forKey: key) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 150)
    }
  }
}

// MARK: - Preview Helper

#Preview("Config Panel Demo") {
  // Demo with a simple test engine
  Text("See EngineConfigPanel usage in debug views")
    .padding()
}
