import SwiftUI

enum DoneButtonPlacement: Sendable {
  case leading
  case trailing
}

struct SettingsWatchSection {
  let isPaired: Bool
  let isWatchAppInstalled: Bool
  let openWatchAppSettings: () -> Void
}

struct SettingsViewCore: View {
  @Binding var isPresented: Bool

  let hasWatch: Bool
  let watchSection: SettingsWatchSection?
  let listStylePlain: Bool
  let includeSweepOverlay: Bool

  @State private var settings = AppSettings.shared

  var body: some View {
    ZStack {
      List {
        ConfigureTVsView()

        if let watchSection, watchSection.isPaired {
          Section("Watch Settings") {
            if watchSection.isWatchAppInstalled {
              SettingRow(
                label: "Launch Screen",
                content: {
                  LaunchScreenPicker(selection: $settings.watchLaunchScreen)
                }
              )

              SettingRow(
                label: "Launch to Media",
                subtitle: "If media is playing, open the Media controls first.",
                content: {
                  Toggle(isOn: $settings.watchAlwaysLaunchToMedia) { EmptyView() }
                    .labelsHidden()
                }
              )
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text("Watch App Not Installed")
                  .font(.headline)
                Text("Open the Watch app on your iPhone to install RockYou on your Apple Watch.")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                Button {
                  watchSection.openWatchAppSettings()
                } label: {
                  HStack {
                    Text("Open Watch App")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                  }
                }
                .buttonStyle(.borderedProminent)
              }
              .padding(.vertical, 8)
            }
          }
        }

        Section("Button Press Safety Delays") {
          SafetyDelaysGrid(
            hasWatch: hasWatch,
            watchPowerDelay: $settings.watchPowerDelay,
            phonePowerDelay: $settings.phonePowerDelay,
            watchHomeDelay: $settings.watchHomeDelay,
            phoneHomeDelay: $settings.phoneHomeDelay,
            watchAppLaunchDelay: $settings.watchAppLaunchDelay,
            phoneAppLaunchDelay: $settings.phoneAppLaunchDelay
          )
        }
      }
      .applyIf(listStylePlain) { view in
        view.listStyle(.plain)
      }

      // iOS: Settings is presented as a sheet above the main root, so we need the overlay
      // mounted inside this host. macOS: Settings is often an inspector in the same window,
      // and the main root already mounts SweepOverlayView(), so mounting it here duplicates it.
      if includeSweepOverlay {
        SweepOverlayView()
      }
    }
  }
}

// MARK: - Small helpers

private extension View {
  @ViewBuilder
  func applyIf<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}

// MARK: - Setting Row

struct SettingRow<Content: View>: View {
  let label: String
  var subtitle: String? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(alignment: subtitle == nil ? .firstTextBaseline : .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .font(.subheadline.weight(.medium))

        if let subtitle {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer()
      content()
    }
    .padding(.vertical, 6)
  }
}

// MARK: - Launch Screen Picker

struct LaunchScreenPicker: View {
  @Binding var selection: LaunchScreen

  var body: some View {
    Picker("", selection: $selection) {
      ForEach(LaunchScreen.allCases, id: \.self) { screen in
        Text(screen.rawValue).tag(screen)
      }
    }
    .pickerStyle(.menu)
  }
}
