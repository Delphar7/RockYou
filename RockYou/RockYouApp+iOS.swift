import SwiftUI
import CloudKit

@main
struct RockYouApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @MainActor
  init() {
    RockYouAppCore.initializeSharedServices()
    // Initialize Watch connectivity for relay architecture (iOS only).
    _ = WatchConnectivityManager.shared
  }

  var body: some Scene {
    WindowGroup("RockYou") {
      ContentViewHost()
    }
    .handlesExternalEvents(matching: ["*"])
  }
}

// MARK: - CloudKit Share Handling (iOS)

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    _ = application
    Log.info(
      "CloudKit",
      "Accepting share from: \(cloudKitShareMetadata.ownerIdentity.nameComponents?.formatted() ?? "unknown")"
    )

    Task {
      do {
        try await PairingStore.shared.acceptShare(metadata: cloudKitShareMetadata)
        Log.info("CloudKit", "Share accepted successfully!")
      } catch {
        Log.error("CloudKit", "Share acceptance failed: \(error.localizedDescription)")
      }
    }
  }
}
