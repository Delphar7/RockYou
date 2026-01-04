//
//  TooltipOverlayView+iOS.swift
//  RockYou (Shared)
//

import SwiftUI

  import UIKit

  /// iOS/iPadOS: render tooltips in a separate pass-through UIWindow (above the entire gesture stack).
  struct TooltipOverlayView: View {
    @ObservedObject var manager = TooltipManager.shared

    var body: some View {
      Color.clear
        .onAppear {
          TooltipWindowPresenter.shared.update(using: manager)
        }
        .onChange(of: manager.message) { _, _ in
          TooltipWindowPresenter.shared.update(using: manager)
        }
        .onChange(of: manager.buttonFrame) { _, _ in
          TooltipWindowPresenter.shared.update(using: manager)
        }
    }
  }

  /// Pass-through overlay window: only receives touches inside `hitRect`, passes everything else
  /// through to the app below.
  private final class TooltipPassthroughWindow: UIWindow {
    var hitRect: CGRect = .zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
      hitRect.contains(point)
    }
  }

  @MainActor
  private final class TooltipWindowPresenter {
    static let shared = TooltipWindowPresenter()

    private var window: TooltipPassthroughWindow?
    private var hostingController: UIHostingController<TooltipWindowContentView>?

    func update(using manager: TooltipManager) {
      guard manager.message != nil else {
        hide()
        return
      }

      let content = TooltipWindowContentView(manager: manager) { [weak self] bubbleRect in
        self?.window?.hitRect = bubbleRect.insetBy(dx: -2, dy: -2)
      }

      if window == nil {
        let w = TooltipPassthroughWindow(frame: UIScreen.main.bounds)
        if let scene = TooltipWindowPresenter.activeWindowScene {
          w.windowScene = scene
        }
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false

        window = w
        hostingController = host
      } else {
        hostingController?.rootView = content
        window?.isHidden = false
      }
    }

    private func hide() {
      window?.isHidden = true
      window?.rootViewController = nil
      hostingController = nil
      window = nil
    }

    private static var activeWindowScene: UIWindowScene? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
        return active
      }
      return scenes.first
    }
  }

  private struct TooltipWindowContentView: View {
    @ObservedObject var manager: TooltipManager
    let onBubbleRect: (CGRect) -> Void

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
          // Keep iPhone tooltips from getting overly wide; prefer wrapping to a 3rd line.
          let maxBubbleWidth: CGFloat = min(260, screenSize.width - (8 * 2))
          let maxTextWidth: CGFloat = max(40, maxBubbleWidth - (bubbleHorizontalPadding * 2))
          let layout = measureTextLayout(message, maxTextWidth: maxTextWidth)
          let bubbleFrame = computeBubbleFrame(
            buttonFrame: localButtonFrame, bubbleSize: layout.bubbleSize, screenSize: screenSize)

          // Keep hit-rect updated for the pass-through window.
          Color.clear
            .onAppear { onBubbleRect(bubbleFrame) }
            .onChange(of: bubbleFrame) { _, newValue in onBubbleRect(newValue) }

          TooltipBubbleShape(
            bubbleFrame: bubbleFrame,
            targetFrame: localButtonFrame,
            baseRatio: 0.20,
            tipDistance: 1.0,
            baseInset: 0.75
          )
          .fill(tooltipColor)
          .shadow(color: .black.opacity(AppOpacity.light), radius: 4, y: 2)
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
            .position(x: bubbleFrame.midX, y: bubbleFrame.midY)
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { manager.dismiss() }
        }
        .ignoresSafeArea()
      } else {
        Color.clear
          .onAppear { onBubbleRect(.zero) }
      }
    }

    private struct TextLayout {
      let textWidth: CGFloat
      let bubbleSize: CGSize
    }

    private func measureTextLayout(_ text: String, maxTextWidth: CGFloat) -> TextLayout {
      let font = UIFont.systemFont(ofSize: tooltipFontSize, weight: .semibold)
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
