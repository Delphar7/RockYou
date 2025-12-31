#!/usr/bin/env swift
//
// IconVisibleBounds.swift
// RockYou
//
// Compute a rough "visible content" bounding box for an RGBA PNG.
// Intended for tuning AppIconWithLabel input-icon vertical centering.
//
// Usage:
//   swift Tools/IconVisibleBounds.swift /path/to/image.png
//   swift Tools/IconVisibleBounds.swift /path/to/image.png --alpha 0.10 --luma 0.15
//

import Foundation
import CoreGraphics
import ImageIO

struct Args {
  let path: String
  let alphaThresh: Double
  let lumaThresh: Double
  let mode: String
  let greenDomThresh: Double
  let greenMin: Double
}

func parseArgs() -> Args? {
  var alpha: Double = 0.10
  var luma: Double = 0.15
  var mode: String = "luma" // "luma" or "green"
  var greenDom: Double = 0.12
  var greenMin: Double = 0.25
  var path: String?

  var i = 1
  while i < CommandLine.arguments.count {
    let a = CommandLine.arguments[i]
    if a == "--alpha", i + 1 < CommandLine.arguments.count {
      alpha = Double(CommandLine.arguments[i + 1]) ?? alpha
      i += 2
      continue
    }
    if a == "--luma", i + 1 < CommandLine.arguments.count {
      luma = Double(CommandLine.arguments[i + 1]) ?? luma
      i += 2
      continue
    }
    if a == "--mode", i + 1 < CommandLine.arguments.count {
      mode = CommandLine.arguments[i + 1]
      i += 2
      continue
    }
    if a == "--green-dom", i + 1 < CommandLine.arguments.count {
      greenDom = Double(CommandLine.arguments[i + 1]) ?? greenDom
      i += 2
      continue
    }
    if a == "--green-min", i + 1 < CommandLine.arguments.count {
      greenMin = Double(CommandLine.arguments[i + 1]) ?? greenMin
      i += 2
      continue
    }
    if !a.hasPrefix("--"), path == nil {
      path = a
      i += 1
      continue
    }
    i += 1
  }

  guard let p = path else { return nil }
  return Args(path: p, alphaThresh: alpha, lumaThresh: luma, mode: mode, greenDomThresh: greenDom, greenMin: greenMin)
}

func loadCGImage(url: URL) -> CGImage? {
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func srgbLuma(r: Double, g: Double, b: Double) -> Double {
  // Simple relative luma in sRGB space (good enough for thresholding).
  0.2126 * r + 0.7152 * g + 0.0722 * b
}

guard let args = parseArgs() else {
  fputs("""
Usage: swift Tools/IconVisibleBounds.swift image.png [options]

Options:
  --alpha N        alpha threshold (default 0.10)
  --luma N         luma threshold (default 0.15) [mode=luma]
  --mode luma|green  pixel selection mode (default luma)
  --green-dom N    require g - max(r,b) >= N (default 0.12) [mode=green]
  --green-min N    require g >= N (default 0.25) [mode=green]

""", stderr)
  exit(2)
}

let url = URL(fileURLWithPath: args.path)
guard let cg = loadCGImage(url: url) else {
  fputs("Failed to load image: \(args.path)\n", stderr)
  exit(1)
}

let w = cg.width
let h = cg.height

let bytesPerPixel = 4
let bytesPerRow = bytesPerPixel * w
let bufSize = bytesPerRow * h
var data = Data(count: bufSize)

data.withUnsafeMutableBytes { rawBuf in
  let ctx = CGContext(
    data: rawBuf.baseAddress,
    width: w,
    height: h,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
}

var minX = w, minY = h, maxX = -1, maxY = -1
let aT = args.alphaThresh
let yT = args.lumaThresh
let mode = args.mode.lowercased()
let greenDomT = args.greenDomThresh
let greenMin = args.greenMin

data.withUnsafeBytes { rawBuf in
  guard let p = rawBuf.bindMemory(to: UInt8.self).baseAddress else {
    fputs("Unexpected nil pixel buffer\n", stderr)
    exit(1)
  }
  for y in 0..<h {
    for x in 0..<w {
      let idx = y * bytesPerRow + x * bytesPerPixel
      let r = Double(p[idx + 0]) / 255.0
      let g = Double(p[idx + 1]) / 255.0
      let b = Double(p[idx + 2]) / 255.0
      let a = Double(p[idx + 3]) / 255.0
      if a < aT { continue }

      switch mode {
      case "green":
        if g < greenMin { continue }
        let dom = g - max(r, b)
        if dom < greenDomT { continue }
      default:
        let l = srgbLuma(r: r, g: g, b: b)
        if l < yT { continue }
      }

      if x < minX { minX = x }
      if y < minY { minY = y }
      if x > maxX { maxX = x }
      if y > maxY { maxY = y }
    }
  }
}

if maxX < 0 || maxY < 0 {
  print("No pixels matched thresholds (alpha>=\(args.alphaThresh), luma>=\(args.lumaThresh)).")
  exit(0)
}

let boxW = maxX - minX + 1
let boxH = maxY - minY + 1

let fracW = Double(boxW) / Double(w)
let fracH = Double(boxH) / Double(h)
let bottomGap = Double(h - 1 - maxY) / Double(h)
let topGap = Double(minY) / Double(h)

print("image=\(url.lastPathComponent) size=\(w)x\(h)")
if mode == "green" {
  print("thresholds alpha>=\(args.alphaThresh) mode=green greenMin>=\(args.greenMin) greenDom>=\(args.greenDomThresh)")
} else {
  print("thresholds alpha>=\(args.alphaThresh) mode=luma luma>=\(args.lumaThresh)")
}
print("bbox x=\(minX)..\(maxX) y=\(minY)..\(maxY) (w=\(boxW) h=\(boxH))")
print(String(format: "fractions w=%.3f h=%.3f topGap=%.3f bottomGap=%.3f", fracW, fracH, topGap, bottomGap))
