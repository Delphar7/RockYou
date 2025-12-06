import SwiftUI

enum SweeperDelayOptions {
  static let options: [TimeInterval?] = [
    5.0, 4.5, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25, nil,
  ]

  static func label(for delay: TimeInterval?) -> String {
    guard let delay else { return "Off" }
    if delay >= 1.0 {
      return String(format: "%.1fs", delay)
    }
    return String(format: "%.2fs", delay)
  }
}

struct SafetyDelaysGrid: View {
  let hasWatch: Bool
  @Binding var watchPowerDelay: TimeInterval?
  @Binding var phonePowerDelay: TimeInterval?
  @Binding var watchHomeDelay: TimeInterval?
  @Binding var phoneHomeDelay: TimeInterval?
  @Binding var watchAppLaunchDelay: TimeInterval?
  @Binding var phoneAppLaunchDelay: TimeInterval?

  private let columnSpacing: CGFloat = 12
  private var rowSpacing: CGFloat {
    PlatformSafetyDelayLayout.rowSpacing(hasWatch: hasWatch)
  }

  private let headerYOffset: CGFloat = PlatformSafetyDelayLayout.headerYOffset
  private let pickerHeight: CGFloat = PlatformSafetyDelayLayout.pickerHeight

  var body: some View {
    Grid(horizontalSpacing: columnSpacing, verticalSpacing: rowSpacing) {
      if hasWatch {
        GridRow {
          Color.clear
            .frame(width: 1)

          headerLabel("Watch")
          headerLabel("Phone")
        }
        .offset(y: headerYOffset)
      }

      GridRow {
        delayLabel("Power")

        if hasWatch {
          CompactDelayPicker(selection: $watchPowerDelay, targetHeight: pickerHeight)
        }

        CompactDelayPicker(
          selection: $phonePowerDelay,
          alignment: .center,
          targetHeight: pickerHeight
        )
      }

      GridRow {
        delayLabel("Home")

        if hasWatch {
          CompactDelayPicker(selection: $watchHomeDelay, targetHeight: pickerHeight)
        }

        CompactDelayPicker(
          selection: $phoneHomeDelay,
          alignment: .center,
          targetHeight: pickerHeight
        )
      }

      GridRow {
        delayLabel("Apps")

        if hasWatch {
          CompactDelayPicker(selection: $watchAppLaunchDelay, targetHeight: pickerHeight)
        }

        CompactDelayPicker(
          selection: $phoneAppLaunchDelay,
          alignment: .center,
          targetHeight: pickerHeight
        )
      }

      GridRow {
        Color.clear
          .frame(height: 8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 1)
  }

  private func headerLabel(_ title: String) -> some View {
    Text(title)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private func delayLabel(_ title: String) -> some View {
    Text(title)
      .font(.body.weight(.medium))
      .fixedSize(horizontal: true, vertical: false)
      .gridCellAnchor(.trailing)
      .padding(.trailing, 4)
  }
}
