import SwiftUI

enum SweeperDelayOptions {
  static let options: [TimeInterval?] = [
    5.0, 4.5, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25, nil,
  ]

  static func label(for delay: TimeInterval?) -> String {
    guard let delay else { return "Off" }
    if delay >= 1.0 {
      return String(format: "%.1fs", delay)
    }
    return String(format: "%.2fs", delay)
  }
}

enum LockTimeoutOptions {
  static let options: [TimeInterval?] = {
    var opts: [TimeInterval?] = [nil, 30.0, 60.0, 300.0, 600.0, 900.0, 1800.0]
    #if DEBUG
      // Debug-only: allow quick testing of the lock behavior.
      opts.insert(5.0, at: 1)
    #endif
    return opts
  }()

  static func options(including selection: TimeInterval?) -> [TimeInterval?] {
    var hasNil = options.contains { $0 == nil }
    var values = options.compactMap { $0 }

    if let selection, !values.contains(selection) {
      values.append(selection)
    }
    values.sort()

    if selection == nil {
      hasNil = true
    }

    if hasNil {
      return [nil] + values
    }
    return values.map { Optional($0) }
  }

  static func label(for timeout: TimeInterval?) -> String {
    guard let timeout else { return "Off" }
    if timeout < 60 {
      return "\(Int(timeout))s"
    }
    let minutes = Int(timeout / 60)
    return "\(minutes)m"
  }
}

struct SafetyDelaysGrid: View {
  let hasWatch: Bool
  @Binding var watchPowerDelay: TimeInterval?
  @Binding var phonePowerDelay: TimeInterval?
  @Binding var watchHomeDelay: TimeInterval?
  @Binding var phoneHomeDelay: TimeInterval?
  @Binding var watchAppLaunchDelay: TimeInterval?
  @Binding var phoneAppLaunchDelay: TimeInterval?
  @Binding var phoneDPadLockTimeout: TimeInterval?

  private let columnSpacing: CGFloat = 12
  private var rowSpacing: CGFloat {
    PlatformSafetyDelayLayout.rowSpacing(hasWatch: hasWatch)
  }

  private let headerYOffset: CGFloat = PlatformSafetyDelayLayout.headerYOffset
  private let pickerHeight: CGFloat = PlatformSafetyDelayLayout.pickerHeight

  var body: some View {
    VStack(alignment: .leading, spacing: rowSpacing) {
      if hasWatch {
        headerRow
          .offset(y: headerYOffset)
      }

      row(
        label: "Power",
        glyph: .symbol("power"),
        watch: hasWatch ? $watchPowerDelay : nil,
        phone: $phonePowerDelay
      )

      row(
        label: "Home",
        glyph: .symbol("house.fill"),
        watch: hasWatch ? $watchHomeDelay : nil,
        phone: $phoneHomeDelay
      )

      row(
        label: "Apps/Channels",
        adornment: .miniAppStrip,
        watch: hasWatch ? $watchAppLaunchDelay : nil,
        phone: $phoneAppLaunchDelay
      )

      dpadLockRow

      Color.clear
        .frame(height: 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 1)
  }

  // MARK: - Rows

  private var headerRow: some View {
    HStack(spacing: columnSpacing) {
      labelCell(Text(""))
      pickerHeaderCell("Watch")
      pickerHeaderCell("Phone")
    }
  }

  private func row(
    label: String,
    glyph: DelayRowGlyph? = nil,
    adornment: DelayRowAdornment? = nil,
    watch: Binding<TimeInterval?>?,
    phone: Binding<TimeInterval?>
  ) -> some View {
    HStack(alignment: .center, spacing: columnSpacing) {
      labelCell(delayLabel(label, glyph: glyph, adornment: adornment))

      if let watch {
        pickerCell(CompactDelayPicker(selection: watch, targetHeight: pickerHeight))
      }

      pickerCell(
        CompactDelayPicker(selection: phone, alignment: .center, targetHeight: pickerHeight)
      )
    }
  }

  private var dpadLockRow: some View {
    HStack(alignment: .center, spacing: columnSpacing) {
      labelCell(delayLabel("D-Pad Lock", glyph: .dpad, adornment: nil))

      if hasWatch {
        // Keep the 3-column grid alignment when there's a watch column.
        pickerCell(Color.clear.frame(height: pickerHeight))
      }

      pickerCell(
        CompactDelayPicker(
          selection: $phoneDPadLockTimeout,
          alignment: .center,
          targetHeight: pickerHeight,
          options: LockTimeoutOptions.options(including: phoneDPadLockTimeout),
          labelFormatter: LockTimeoutOptions.label(for:)
        )
      )
    }
  }

  // MARK: - Column sizing

  /// Weighted columns instead of Grid's "ideal width" sizing (wheel-style Picker is a bad citizen).
  /// With Watch: label/watch/phone = 4:3:3 (40/30/30) without hardcoding pixels.
  /// No Watch: label/phone = 4:6 (40/60) to keep the picker generous.
  private var columnCount: Int { 10 }
  private var labelSpan: Int { 4 }
  private var pickerSpan: Int { hasWatch ? 3 : 6 }

  private func labelCell<V: View>(_ view: V) -> some View {
    view.containerRelativeFrame(
      .horizontal, count: columnCount, span: labelSpan, spacing: columnSpacing)
  }

  private func pickerCell<V: View>(_ view: V) -> some View {
    view.containerRelativeFrame(
      .horizontal, count: columnCount, span: pickerSpan, spacing: columnSpacing)
  }

  private func pickerHeaderCell(_ title: String) -> some View {
    Text(title)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .center)
      .containerRelativeFrame(
        .horizontal, count: columnCount, span: pickerSpan, spacing: columnSpacing)
  }

  private func delayLabel(_ title: String) -> some View {
    delayLabel(title, glyph: nil, adornment: nil)
  }

  private enum DelayRowGlyph: Sendable {
    case symbol(String)
    case dpad
  }

  private enum DelayRowAdornment: Sendable {
    case miniAppStrip
  }

  private func delayLabel(_ title: String, glyph: DelayRowGlyph?, adornment: DelayRowAdornment?)
    -> some View
  {
    let glyphSize = min(pickerHeight, 32)

    return VStack(alignment: .trailing, spacing: 4) {
      HStack(spacing: 8) {
        if let glyph {
          delayGlyph(glyph, size: glyphSize)
        }

        Spacer(minLength: 2)

        AdaptiveTextView(title: title)
      }
      .frame(maxWidth: .infinity)

      if let adornment {
        switch adornment {
        case .miniAppStrip:
          MiniAppStripPlaceholder(rowHeight: pickerHeight)
        }
      }
    }
    .padding(.trailing, 4)
  }

  @ViewBuilder
  private func delayGlyph(_ glyph: DelayRowGlyph, size: CGFloat) -> some View {
    switch glyph {
    case .dpad:
      DPadGlyph(size: size)
        .accessibilityHidden(true)
    case .symbol(let systemName):
      // Reuse the exact TopKeyButton look from the remote UI (rectangular + Roku purple),
      // but make it non-interactive so it doesn’t “push”.
      let height = min(size, 44)
      let width =
        height * (RemoteCoreButtonMetrics.topKeyWidth / RemoteCoreButtonMetrics.topKeyHeight)
      TopKeyButton(
        systemName: systemName,
        width: width,
        height: height,
        baseColor: rokuPurple
      ) {}
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}
/// Adaptive text view that shrinks font size to fit on 1 line, or wraps to 2 lines at a minimum font size.
private struct AdaptiveTextView: View {
  let title: String
  @State private var isSingleLine: Bool = true

  private let minFontSize: CGFloat = 14
  private let maxFontSize: CGFloat = 16

  var body: some View {
    ViewThatFits(in: .horizontal) {
      // Try single line with max font size first
      Text(title)
        .font(.body.weight(.medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear {
          isSingleLine = true
        }

      // Fall back to 2 lines if it doesn't fit
      Text(title)
        .font(.system(size: minFontSize, weight: .medium))
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear {
          isSingleLine = false
        }
    }
  }
}
/// Purely-visual app strip “label” (no gestures, no scrolling, no device state).
private struct MiniAppStripPlaceholder: View {
  let rowHeight: CGFloat

  private var iconSize: CGFloat { min(16, rowHeight * 0.22) }
  private var iconCornerRadius: CGFloat { iconSize * 0.25 }
  private var spacing: CGFloat { max(3, iconSize * 0.15) }

  private let samples: [(name: String, id: String?)] = [
    ("Netflix", RokuAppID.netflix),
    ("Prime Video", RokuAppID.primeVideo),
    ("YouTube", RokuAppID.youtube),
    ("Hulu", RokuAppID.hulu),
    ("Disney+", RokuAppID.disneyPlus),
    ("Max", RokuAppID.max),
    ("Plex", RokuAppID.plex),
    ("Roku", RokuAppID.theRokuChannel),
  ]

  var body: some View {
    HStack(spacing: spacing) {
      ForEach(Array(samples.enumerated()), id: \.offset) { _, item in
        let bg = AppBranding.color(for: item.name, appId: item.id).opacity(0.95)
        let initials = AppBranding.initials(for: item.name, appId: item.id)

        RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
          .fill(bg)
          .overlay(
            Text(initials)
              .font(.system(size: max(8, iconSize * 0.52), weight: .bold, design: .rounded))
              .foregroundStyle(.white.opacity(0.92))
          )
          .frame(width: iconSize, height: iconSize * 0.75)
      }
    }
    .accessibilityHidden(true)
  }
}
