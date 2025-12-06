import SwiftUI
import CloudKit
import AppKit

@main
struct RockYouApp: App {
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate

  @MainActor
  init() {
    RockYouAppCore.initializeSharedServices()
  }

  var body: some Scene {
    // Main remote window
    Window("RockYou", id: "main") {
      ContentViewHost()
        .onDisappear { NSApp.terminate(nil) }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
    .defaultSize(width: 960, height: 720)
    .handlesExternalEvents(matching: ["*"])
    .commands {
      CommandGroup(replacing: .newItem) {}

      CommandGroup(after: .windowArrangement) {
        Divider()
        OpenProtocolExplorerButton()
          .keyboardShortcut("P", modifiers: [.command, .option])
      }

      if DebugBuild.isEnabled {
        CommandMenu("Debug") {
          Button("Inject Test Roku TV") {
            RokuDiscoveryService.shared.debugInjectTestRokuTV()
          }

          Button("Expire Test Roku TV") {
            RokuDiscoveryService.shared.debugExpireTestRokuTV()
          }
        }
      }
    }

    // Protocol Explorer window (dev tool)
    Window("Protocol Explorer", id: "protocol-explorer") {
      ProtocolExplorerView()
    }
    .defaultSize(width: 1100, height: 700)
  }
}

/// Button to open Protocol Explorer window (needs separate struct to use @Environment).
private struct OpenProtocolExplorerButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Protocol Explorer") {
      openWindow(id: "protocol-explorer")
    }
  }
}

// MARK: - CloudKit Share Handling (macOS)

final class MacAppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    _ = application
    Log.info(
      "CloudKit",
      "Accepting share from: \(metadata.ownerIdentity.nameComponents?.formatted() ?? "unknown")"
    )

    Task {
      do {
        try await PairingStore.shared.acceptShare(metadata: metadata)
        Log.info("CloudKit", "Share accepted successfully!")
      } catch {
        Log.error("CloudKit", "Share acceptance failed: \(error.localizedDescription)")
      }
    }
  }
}
