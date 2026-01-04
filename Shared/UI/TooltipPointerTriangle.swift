//
//  TooltipPointerTriangle.swift
//  RockYou (Shared)
//
//  Shared tooltip pointer triangle shape used by TooltipOverlayView implementations.
//

import SwiftUI

struct TooltipPointerTriangle: Shape {
  let bubbleFrame: CGRect
  let targetFrame: CGRect
  let baseRatio: CGFloat
  let tipDistance: CGFloat
  /// How far to inset the triangle base into the bubble to avoid anti-alias seams.
  /// A small positive value makes the triangle slightly overlap the bubble.
  let baseInset: CGFloat

  func path(in rect: CGRect) -> Path {
    _ = rect

    let direction = CGPoint(
      x: targetFrame.midX - bubbleFrame.midX,
      y: targetFrame.midY - bubbleFrame.midY
    )
    let dirLen = hypot(direction.x, direction.y)
    guard dirLen > 0.0001 else { return Path() }
    let dirUnit = CGPoint(x: direction.x / dirLen, y: direction.y / dirLen)

    // Find where ray crosses each frame boundary
    let (p1, edge) = findRayCrossing(
      from: CGPoint(x: bubbleFrame.midX, y: bubbleFrame.midY),
      direction: direction,
      frame: bubbleFrame
    )
    let (p2, _) = findRayCrossing(
      from: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
      direction: CGPoint(x: -direction.x, y: -direction.y),
      frame: targetFrame
    )

    // Base vector runs along the crossed edge
    let isHorizontalEdge = (edge == .top || edge == .bottom)
    let baseVector = isHorizontalEdge ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1)
    let edgeLength = isHorizontalEdge ? bubbleFrame.width : bubbleFrame.height
    let baseHalf = (edgeLength * baseRatio) / 2

    let (minBound, maxBound) =
      isHorizontalEdge
      ? (bubbleFrame.minX, bubbleFrame.maxX)
      : (bubbleFrame.minY, bubbleFrame.maxY)

    // Inset base slightly into the bubble so triangle and bubble overlap (eliminates seam).
    let p1Inset = CGPoint(x: p1.x - dirUnit.x * baseInset, y: p1.y - dirUnit.y * baseInset)
    let base1 = clampedBasePoint(
      p1Inset, baseVector: baseVector, offset: -baseHalf, bounds: (minBound, maxBound))
    let base2 = clampedBasePoint(
      p1Inset, baseVector: baseVector, offset: baseHalf, bounds: (minBound, maxBound))

    // Triangle tip is partway from P1 toward P2
    let tip = CGPoint(
      x: p1.x + (p2.x - p1.x) * tipDistance,
      y: p1.y + (p2.y - p1.y) * tipDistance
    )

    var path = Path()
    path.move(to: base1)
    path.addLine(to: tip)
    path.addLine(to: base2)
    path.closeSubpath()
    return path
  }

  // MARK: - Helpers

  private enum Edge { case top, bottom, left, right }

  /// Find where a ray from `from` in `direction` first exits `frame`.
  private func findRayCrossing(from: CGPoint, direction: CGPoint, frame: CGRect) -> (CGPoint, Edge)
  {
    let edges: [(boundary: CGFloat, edge: Edge, isVertical: Bool)] = [
      (frame.maxX, .right, true),
      (frame.minX, .left, true),
      (frame.maxY, .bottom, false),
      (frame.minY, .top, false),
    ]

    var minT: CGFloat = .greatestFiniteMagnitude
    var result = (from, Edge.right)

    for (boundary, edge, isVertical) in edges {
      let d = isVertical ? direction.x : direction.y
      let c = isVertical ? from.x : from.y
      guard d != 0 else { continue }

      let t = (boundary - c) / d
      guard t > 0, t < minT else { continue }

      let perpC = isVertical ? from.y : from.x
      let perpD = isVertical ? direction.y : direction.x
      let crossPerp = perpC + t * perpD
      let (perpMin, perpMax) =
        isVertical
        ? (frame.minY, frame.maxY)
        : (frame.minX, frame.maxX)

      if crossPerp >= perpMin && crossPerp <= perpMax {
        minT = t
        let crossPoint =
          isVertical
          ? CGPoint(x: boundary, y: crossPerp)
          : CGPoint(x: crossPerp, y: boundary)
        result = (crossPoint, edge)
      }
    }

    return result
  }

  private func clampedBasePoint(
    _ p: CGPoint, baseVector: CGPoint, offset: CGFloat, bounds: (CGFloat, CGFloat)
  ) -> CGPoint {
    var result = CGPoint(x: p.x + baseVector.x * offset, y: p.y + baseVector.y * offset)
    if baseVector.x != 0 {
      result.x = max(bounds.0, min(bounds.1, result.x))
    } else {
      result.y = max(bounds.0, min(bounds.1, result.y))
    }
    return result
  }
}

/// A single, contiguous tooltip bubble shape (capsule + pointer).
/// Drawing this as one filled shape avoids gaps/edges where the pointer meets the capsule.
struct TooltipBubbleShape: Shape {
  let bubbleFrame: CGRect
  let targetFrame: CGRect
  let baseRatio: CGFloat
  let tipDistance: CGFloat
  let baseInset: CGFloat

  func path(in rect: CGRect) -> Path {
    _ = rect
    var p = Path()
    p.addPath(Capsule(style: .continuous).path(in: bubbleFrame))
    p.addPath(
      TooltipPointerTriangle(
        bubbleFrame: bubbleFrame,
        targetFrame: targetFrame,
        baseRatio: baseRatio,
        tipDistance: tipDistance,
        baseInset: baseInset
      ).path(in: .zero)
    )
    return p
  }
}
