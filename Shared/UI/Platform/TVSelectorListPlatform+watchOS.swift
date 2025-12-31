import SwiftUI

enum TVSelectorListPlatform {
  static var emptyStateFontSize: CGFloat { 12 }
  static var progressScale: CGFloat { 0.6 }

  static func itemsList(
    items: [TVSelectorItem],
    selectedId: String?,
    onSelect: @escaping (String) -> Void
  ) -> AnyView {
    AnyView(
      List {
        ForEach(items) { item in
          TVSelectorRow(
            item: item,
            isSelected: item.selectionId == selectedId,
            onSelect: { onSelect(item.selectionId) }
          )
          .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
          .listRowBackground(Color.black.opacity(AppOpacity.standard))
        }
      }
      .environment(\.defaultMinListRowHeight, 36)
      .scrollContentBackground(.hidden)
    )
  }

  static func rowChrome<Base: View>(_ base: Base, isSelected: Bool) -> AnyView {
    AnyView(
      base
        .overlay(
          RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
            .strokeBorder(
              isSelected ? Color.white.opacity(0.35) : Color.clear,
              lineWidth: isSelected ? 1 : 0
            )
            // Expand outward so the border feels like it surrounds the row rather than cutting into it.
            .padding(-3)
        )
    )
  }

  static var rowCornerRadius: CGFloat { 10 }

  static var rowIconXOffset: CGFloat { 3 }

  static var rowTextLineSpacing: CGFloat { 1 }

  static var rowIconSize: CGFloat { 20 }
  static var rowIconSpacing: CGFloat { 6 }
  static var rowPrimaryFontSize: CGFloat { 13 }
  static var rowSecondaryFontSize: CGFloat { 10 }
}
