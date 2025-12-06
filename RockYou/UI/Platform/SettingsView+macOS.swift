import SwiftUI

struct SettingsView: View {
  @Binding var isPresented: Bool
  var doneButtonPlacement: DoneButtonPlacement = .trailing

  var body: some View {
    SettingsViewCore(
      isPresented: $isPresented,
      hasWatch: false,
      watchSection: nil,
      listStylePlain: false,
      includeSweepOverlay: false
    )
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
