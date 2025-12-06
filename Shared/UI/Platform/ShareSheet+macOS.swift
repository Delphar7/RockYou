//
//  ShareSheet+macOS.swift
//  RockYou (Shared)
//
//  macOS share UX: copy URL to clipboard and show a small confirmation panel.
//

import AppKit
import SwiftUI

struct ShareSheet: View {
  let items: [Any]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 16) {
      Text("Share link copied!")
        .font(.headline)

      if let url = items.first as? URL {
        Text(url.absoluteString)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Button("Done") { dismiss() }
        .buttonStyle(.borderedProminent)
    }
    .padding(24)
    .frame(minWidth: 300)
    .onAppear {
      if let url = items.first as? URL {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
      }
    }
  }
}
