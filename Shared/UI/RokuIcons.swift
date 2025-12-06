//
//  RokuIcons.swift
//  RockYou
//
//  Roku-branded icons for TVs and streaming devices.
//

import SwiftUI

// MARK: - Roku TV Icon (TV with Roku branding inside)

struct RokuTVIcon: View {
  var size: CGFloat = 28
  var powerMode: PowerMode = .unknown

  var body: some View {
    ZStack {
      // TV frame outline
      RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
        .fill(Color.gray.opacity(AppOpacity.standard))
        .frame(width: size, height: size * 0.72)

      // Screen area - connection status color
      RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
        .fill(powerMode.statusColor)
        .frame(width: size * 0.85, height: size * 0.58)

      // Roku "R" text - always bright white
      Text("R")
        .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.white)

      // TV stand
      VStack(spacing: 0) {
        Spacer()
        RoundedRectangle(cornerRadius: 1)
          .fill(Color.gray.opacity(AppOpacity.moderate))
          .frame(width: size * 0.5, height: size * 0.06)
          .offset(y: size * 0.02)
      }
      .frame(width: size, height: size * 0.8)
    }
    .frame(width: size, height: size * 0.8)
  }
}

// MARK: - Streaming Device Icon

struct StreamingDeviceIcon: View {
  var size: CGFloat = 20
  var powerMode: PowerMode = .unknown

  var body: some View {
    ZStack {
      // Device body - connection status color
      RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        .fill(powerMode.statusColor)
        .frame(width: size, height: size * 0.55)

      // Roku "R" - always bright white
      Text("R")
        .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.white)
    }
    .frame(width: size, height: size * 0.55)
  }
}

#Preview("RokuTVIcon") {
  HStack(spacing: 20) {
    RokuTVIcon(size: 28)
    RokuTVIcon(size: 40)
    RokuTVIcon(size: 60)
  }
  .padding()
  .background(Color.black)
}

#Preview("StreamingDeviceIcon") {
  HStack(spacing: 20) {
    StreamingDeviceIcon(size: 20)
    StreamingDeviceIcon(size: 30)
    StreamingDeviceIcon(size: 40)
  }
  .padding()
  .background(Color.black)
}
