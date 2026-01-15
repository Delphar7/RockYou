import SwiftUI

@MainActor
enum AppSettingsPlatform {
  static func syncToWatch() {}
}
struct SettingsView: View {
  @Binding var isPresented: Bool
  var doneButtonPlacement: DoneButtonPlacement = .trailing

  var body: some View {
    List {
      ConfigureTVsView()

    SettingsViewCore(
      hasWatch: false,
      watchSection: nil,
      showSafetyDelays: false
    )
    }
    .toolbar {
      if isPresented {
        ToolbarItem(placement: .primaryAction) {
          doneButton
        }
      }
    }
  }

  private var doneButton: some View {
    Button {
      isPresented = false
    } label: {
      Text("Done")
        .padding(.leading, 12)
        .padding(.trailing, 8)
    }
  }
}
