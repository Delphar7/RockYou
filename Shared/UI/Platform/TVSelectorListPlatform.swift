import SwiftUI

enum TVSelectorListPlatform {
  static var emptyStateFontSize: CGFloat {
    return 13
  }

  static var progressScale: CGFloat {
    return 0.7
  }

  static func itemsList(
    items: [TVSelectorItem],
    selectedId: String?,
    onSelect: @escaping (String) -> Void
  ) -> AnyView {
    return AnyView(
      VStack(spacing: 4) {
        ForEach(items) { item in
          TVSelectorRow(
            item: item,
            isSelected: item.selectionId == selectedId,
            onSelect: { onSelect(item.selectionId) }
          )
        }
      }
      .frame(maxWidth: 512)
    )
  }

  static func rowChrome<Base: View>(_ base: Base, isSelected: Bool) -> AnyView {
    return AnyView(
      base
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
            .strokeBorder(
              isSelected ? Color.white.opacity(0.35) : Color.clear,
              lineWidth: isSelected ? 1 : 0
            )
        )
    )
  }

  static var rowCornerRadius: CGFloat { 8 }

  /// Horizontal nudge for the device icon inside a row.
  /// Useful for small optical alignment tweaks per platform.
  static var rowIconXOffset: CGFloat { 0 }

  /// Vertical spacing between the primary and secondary text lines in a row.
  static var rowTextLineSpacing: CGFloat { 2 }

  static var rowIconSize: CGFloat {
    return 28
  }

  static var rowIconSpacing: CGFloat {
    return 10
  }

  static var rowPrimaryFontSize: CGFloat {
    return 14
  }

  static var rowSecondaryFontSize: CGFloat {
    return 12
  }

}
