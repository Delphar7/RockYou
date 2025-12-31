//
//  PageIndicator.swift
//  RockYou Watch App
//
//  Simple page dots indicator.
//

import SwiftUI

struct PageIndicator: View {
  let pageCount: Int
  let currentPage: Int
  var onPageTap: ((Int) -> Void)? = nil
  var dotSize: CGFloat = 8
  var spacing: CGFloat = 8

  var body: some View {
    HStack(spacing: spacing) {
      ForEach(0..<pageCount, id: \.self) { index in
        Circle()
          .fill(index == currentPage ? Color.white : Color.white.opacity(AppOpacity.standard))
          .frame(width: dotSize, height: dotSize)
          .contentShape(Circle().scale(2.5))  // Larger tap target
          .onTapGesture {
            if index != currentPage {
              onPageTap?(index)
            }
          }
      }
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    PageIndicator(pageCount: 2, currentPage: 0)
    PageIndicator(pageCount: 2, currentPage: 1)
    PageIndicator(pageCount: 3, currentPage: 1)
  }
  .padding()
  .background(Color.black)
}
