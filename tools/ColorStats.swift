#!/usr/bin/env swift
//
//  ColorStats.swift
//  RockYou (tools)
//
//  Usage:
//    swift Tools/ColorStats.swift [--ignore-white=THRESH] [--ignore-alpha-below=N] path/to/image.png [path/to/other.png ...]
//
//  Prints average RGBA (0-255), median RGBA (0-255), and derived HSV (H in degrees, S/V 0-1).
//  No third-party deps; uses CoreGraphics/ImageIO.
//

import Foundation
import CoreGraphics
import ImageIO

struct RGBAStats {
  let width: Int
  let height: Int
  let includedPixelCount: Int
  let totalPixelCount: Int
  let avg: (Double, Double, Double, Double) // 0-255
  let med: (Int, Int, Int, Int)             // 0-255
  let hsv: (Double, Double, Double)         // H in degrees, S/V 0-1
}

struct FilterOptions {
  /// If set, pixels with R/G/B all >= threshold are excluded (useful for ignoring white glyphs).
  var ignoreWhiteThreshold: Int? = nil
  /// Exclude pixels with alpha < this threshold (0-255). Defaults to 1 (i.e. keep all opaque pixels).
  var ignoreAlphaBelow: Int = 1

  func includes(r: Int, g: Int, b: Int, a: Int) -> Bool {
    if a < ignoreAlphaBelow { return false }
    if let t = ignoreWhiteThreshold, r >= t, g >= t, b >= t { return false }
    return true
  }
}

func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
  let maxv = max(r, max(g, b))
  let minv = min(r, min(g, b))
  let delta = maxv - minv

  var h: Double = 0
  if delta != 0 {
    if maxv == r {
      h = (g - b) / delta
    } else if maxv == g {
      h = 2 + (b - r) / delta
    } else {
      h = 4 + (r - g) / delta
    }
    h *= 60
    if h < 0 { h += 360 }
  }

  let s: Double = maxv == 0 ? 0 : (delta / maxv)
  let v: Double = maxv
  return (h, s, v)
}

func medianFromHist(_ hist: [Int], total: Int) -> Int {
  let target = total / 2
  var running = 0
  for i in 0..<hist.count {
    running += hist[i]
    if running > target { return i }
  }
  return hist.count - 1
}

func loadCGImage(url: URL) -> CGImage? {
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func stats(for path: String, filter: FilterOptions) throws -> RGBAStats {
  let url = URL(fileURLWithPath: path)
  guard let image = loadCGImage(url: url) else {
    throw NSError(
      domain: "ColorStats",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Failed to load image: \(path)"]
    )
  }

  let width = image.width
  let height = image.height
  let count = width * height

  var pixels = [UInt8](repeating: 0, count: count * 4)
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

  guard let ctx = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
  ) else {
    throw NSError(
      domain: "ColorStats",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"]
    )
  }

  ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

  var sr: Double = 0, sg: Double = 0, sb: Double = 0, sa: Double = 0
  var included = 0
  var hr = [Int](repeating: 0, count: 256)
  var hg = [Int](repeating: 0, count: 256)
  var hb = [Int](repeating: 0, count: 256)
  var ha = [Int](repeating: 0, count: 256)

  for i in stride(from: 0, to: pixels.count, by: 4) {
    let r = Int(pixels[i + 0])
    let g = Int(pixels[i + 1])
    let b = Int(pixels[i + 2])
    let a = Int(pixels[i + 3])

    guard filter.includes(r: r, g: g, b: b, a: a) else { continue }
    included += 1

    sr += Double(r)
    sg += Double(g)
    sb += Double(b)
    sa += Double(a)

    hr[r] += 1
    hg[g] += 1
    hb[b] += 1
    ha[a] += 1
  }

  guard included > 0 else {
    throw NSError(
      domain: "ColorStats",
      code: 3,
      userInfo: [NSLocalizedDescriptionKey: "All pixels filtered out for image: \(path)"]
    )
  }

  let avgR = sr / Double(included)
  let avgG = sg / Double(included)
  let avgB = sb / Double(included)
  let avgA = sa / Double(included)

  let medR = medianFromHist(hr, total: included)
  let medG = medianFromHist(hg, total: included)
  let medB = medianFromHist(hb, total: included)
  let medA = medianFromHist(ha, total: included)

  let hsv = rgbToHSV(r: avgR / 255.0, g: avgG / 255.0, b: avgB / 255.0)

  return RGBAStats(
    width: width,
    height: height,
    includedPixelCount: included,
    totalPixelCount: count,
    avg: (avgR, avgG, avgB, avgA),
    med: (medR, medG, medB, medA),
    hsv: (hsv.h, hsv.s, hsv.v)
  )
}

func fmtAvg(_ x: (Double, Double, Double, Double)) -> String {
  String(format: "%.3f, %.3f, %.3f, %.3f", x.0, x.1, x.2, x.3)
}

func main() throws {
  let args = Array(CommandLine.arguments.dropFirst())
  guard !args.isEmpty else {
    fputs("Usage: swift Tools/ColorStats.swift [--ignore-white=THRESH] [--ignore-alpha-below=N] path/to/image.png [path/to/other.png ...]\n", stderr)
    exit(2)
  }

  var filter = FilterOptions()
  var paths: [String] = []

  for arg in args {
    if arg.hasPrefix("--ignore-white=") {
      let v = String(arg.dropFirst("--ignore-white=".count))
      filter.ignoreWhiteThreshold = Int(v)
    } else if arg.hasPrefix("--ignore-alpha-below=") {
      let v = String(arg.dropFirst("--ignore-alpha-below=".count))
      filter.ignoreAlphaBelow = Int(v) ?? filter.ignoreAlphaBelow
    } else if arg.hasPrefix("--") {
      fputs("Unknown option: \(arg)\n", stderr)
      exit(2)
    } else {
      paths.append(arg)
    }
  }

  guard !paths.isEmpty else {
    fputs("No image paths provided.\n", stderr)
    exit(2)
  }

  for path in paths {
    let s = try stats(for: path, filter: filter)
    let pct = (Double(s.includedPixelCount) / Double(s.totalPixelCount)) * 100.0
    let pctStr = String(format: "%.1f", pct)
    print("\(path)  size=\(s.width)x\(s.height)  included=\(s.includedPixelCount)/\(s.totalPixelCount) (\(pctStr)%)")
    print("  avg RGBA (0-255): \(fmtAvg(s.avg))")
    print("  med RGBA (0-255): \(s.med.0), \(s.med.1), \(s.med.2), \(s.med.3)")
    print(String(format: "  avg HSV: H=%.2f°, S=%.4f, V=%.4f", s.hsv.0, s.hsv.1, s.hsv.2))
  }
}

do {
  try main()
} catch {
  fputs("ColorStats error: \(error)\n", stderr)
  exit(1)
}
