import SwiftUI

extension View {
  func platformSettingsPresentation<SheetContent: View, PanelContent: View, InspectorContent: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder sheet: @escaping () -> SheetContent,
    @ViewBuilder panel: @escaping () -> PanelContent,
    @ViewBuilder inspector: @escaping () -> InspectorContent
  ) -> some View {
    _ = inspector

    let sheetIsPresented = Binding(
      get: { isPresented.wrappedValue && !PlatformDevice.isPad },
      set: { newValue in
        if isPresented.wrappedValue != newValue {
          isPresented.wrappedValue = newValue
        }
      }
    )

    let panelIsPresented = Binding(
      get: { isPresented.wrappedValue && PlatformDevice.isPad },
      set: { newValue in
        if isPresented.wrappedValue != newValue {
          isPresented.wrappedValue = newValue
        }
      }
    )

    return
      self
      .sheet(isPresented: sheetIsPresented) {
        sheet()
          .presentationDetents([.fraction(0.86)])
          .presentationDragIndicator(.visible)
          .presentationBackground(Color(white: 0.12))
      }
      .edgePanel(
        isPresented: panelIsPresented,
        anchor: .trailing,
        preferredWidth: 420,
        allowsTapToDismiss: true
      ) {
        panel()
      }
  }
}

// MARK: - Collapsible Settings Section

/// iOS: Wraps content in a DisclosureGroup for collapsible sections
struct PlatformSettingsSection<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content

  var body: some View {
    DisclosureGroup(
      isExpanded: $isExpanded,
      content: content,
      label: {
        Text(title)
          .font(.headline)
      }
    )
  }
}