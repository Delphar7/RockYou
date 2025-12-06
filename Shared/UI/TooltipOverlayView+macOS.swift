//
//  TooltipOverlayView+macOS.swift
//  RockYou (Shared)
//

import SwiftUI

  import AppKit

  struct TooltipOverlayView: View {
    @ObservedObject var manager = TooltipManager.shared

    private let tooltipColor = Color(red: 1, green: 1, blue: 0.9)
    private let textColor = rokuPurple
    private let tooltipFontSize: CGFloat = 14
    private let bubbleHorizontalPadding: CGFloat = 10
    private let bubbleVerticalPadding: CGFloat = 6

    var body: some View {
      if let message = manager.message {
        GeometryReader { geo in
          let screenSize = geo.size
          let globalOrigin = geo.frame(in: .global).origin
          let localButtonFrame = CGRect(
            x: manager.buttonFrame.minX - globalOrigin.x,
            y: manager.buttonFrame.minY - globalOrigin.y,
            width: manager.buttonFrame.width,
            height: manager.buttonFrame.height
          )
          let maxBubbleWidth: CGFloat = min(420, screenSize.width - (8 * 2))
          let maxTextWidth: CGFloat = max(80, maxBubbleWidth - (bubbleHorizontalPadding * 2))
          let layout = measureTextLayout(message, maxTextWidth: maxTextWidth)
          let bubbleFrame = computeBubbleFrame(
            buttonFrame: localButtonFrame, bubbleSize: layout.bubbleSize, screenSize: screenSize)
          let bubbleFrameGlobal = CGRect(
            x: bubbleFrame.minX + globalOrigin.x,
            y: bubbleFrame.minY + globalOrigin.y,
            width: bubbleFrame.width,
            height: bubbleFrame.height
          )

          // Tap anywhere to dismiss (macOS).
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { manager.dismiss() }

          TooltipBubbleFrameReporter(manager: manager, bubbleFrameGlobal: bubbleFrameGlobal)
            .allowsHitTesting(false)

          TooltipPointerTriangle(
            bubbleFrame: bubbleFrame,
            targetFrame: localButtonFrame,
            baseRatio: 0.20,
            tipDistance: 1.0
          )
          .fill(tooltipColor)
          .allowsHitTesting(false)

          Text(message)
            .font(.system(size: tooltipFontSize, weight: .semibold))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .minimumScaleFactor(1.0)
            .allowsTightening(false)
            .frame(width: layout.textWidth)
            .padding(.horizontal, bubbleHorizontalPadding)
            .padding(.vertical, bubbleVerticalPadding)
            .background(tooltipColor)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(AppOpacity.light), radius: 4, y: 2)
            .position(x: bubbleFrame.midX, y: bubbleFrame.midY)
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { manager.dismiss() }
        }
        .ignoresSafeArea()
      }
    }

    private struct TextLayout {
      let textWidth: CGFloat
      let bubbleSize: CGSize
    }

    private func measureTextLayout(_ text: String, maxTextWidth: CGFloat) -> TextLayout {
      let font = NSFont.systemFont(ofSize: tooltipFontSize, weight: .semibold)
      let rect = (text as NSString).boundingRect(
        with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font],
        context: nil
      ).integral
      let textWidth = min(maxTextWidth, rect.width.rounded(.up))
      let textHeight = rect.height.rounded(.up)
      return TextLayout(
        textWidth: textWidth,
        bubbleSize: CGSize(
          width: textWidth + (bubbleHorizontalPadding * 2),
          height: textHeight + (bubbleVerticalPadding * 2)
        )
      )
    }

    private func computeBubbleFrame(buttonFrame: CGRect, bubbleSize: CGSize, screenSize: CGSize)
      -> CGRect
    {
      let margin: CGFloat = 8
      let verticalGap: CGFloat = 24
      let horizontalOffset: CGFloat = 80

      let buttonOnRight = buttonFrame.midX > screenSize.width / 2
      let idealX =
        buttonOnRight
        ? buttonFrame.midX - horizontalOffset
        : buttonFrame.midX + horizontalOffset
      let bubbleX = max(
        bubbleSize.width / 2 + margin,
        min(screenSize.width - bubbleSize.width / 2 - margin, idealX))

      let spaceBelow = screenSize.height - buttonFrame.maxY
      let needsSpace = bubbleSize.height + verticalGap + margin

      let bubbleY: CGFloat
      if spaceBelow >= needsSpace {
        bubbleY = buttonFrame.maxY + verticalGap + bubbleSize.height / 2
      } else {
        bubbleY = buttonFrame.minY - verticalGap - bubbleSize.height / 2
      }

      return CGRect(
        x: bubbleX - bubbleSize.width / 2,
        y: bubbleY - bubbleSize.height / 2,
        width: bubbleSize.width,
        height: bubbleSize.height
      )
    }
  }

  private struct TooltipBubbleFrameReporter: View {
    @ObservedObject var manager: TooltipManager
    let bubbleFrameGlobal: CGRect

    var body: some View {
      Color.clear
        .onAppear { manager.bubbleFrame = bubbleFrameGlobal }
        .onChange(of: bubbleFrameGlobal) { _, newValue in
          manager.bubbleFrame = newValue
        }
    }
  }
