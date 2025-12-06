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

  static func rowChrome<Base: View>(_ base: Base) -> AnyView {
    return AnyView(
      base
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    )
  }

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

  static var rowCheckmarkSize: CGFloat {
    return 12
  }
}
