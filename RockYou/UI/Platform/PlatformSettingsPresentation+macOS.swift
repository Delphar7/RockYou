import SwiftUI

extension View {
  func platformSettingsPresentation<SheetContent: View, PanelContent: View, InspectorContent: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder sheet: @escaping () -> SheetContent,
    @ViewBuilder panel: @escaping () -> PanelContent,
    @ViewBuilder inspector: @escaping () -> InspectorContent
  ) -> some View {
    _ = sheet
    _ = panel

    return self
      .onTapGesture {
        if isPresented.wrappedValue {
          isPresented.wrappedValue = false
        }
      }
      .inspector(isPresented: isPresented) {
        inspector()
      }
  }
}

// MARK: - Collapsible Settings Section

/// macOS: Just renders as a regular Section (no collapsing)
struct PlatformSettingsSection<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content

  var body: some View {
    Section(title) {
      content()
    }
  }
}
