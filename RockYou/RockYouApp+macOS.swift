import AppKit
import CloudKit
import ObjectiveC
import SwiftUI

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
    // Note: `contentMinSize` inference is unreliable with GeometryReader-heavy layouts.
    // We enforce the minimum in `MacAppDelegate` via NSWindow.contentMinSize.
    .handlesExternalEvents(matching: ["*"])
    .commands { appCommands }

    // Protocol Explorer window (dev tool)
    Window("Protocol Explorer", id: "protocol-explorer") {
      ProtocolExplorerView()
    }
    .defaultSize(width: 1100, height: 700)

    #if DEBUG
      Window("Debug Render — Dome", id: "debug-render-dome") {
        DomeRenderDebugView()
      }
      .defaultSize(width: 1000, height: 760)

      Window("Debug Render — Breaker", id: "debug-render-breaker") {
        BreakerRenderDebugView()
      }
      .defaultSize(width: 900, height: 720)

      Window("Debug — Playground: Dome", id: "debug-playground-dome") {
        DomePlaygroundView()
      }
      .defaultSize(width: 950, height: 700)
    #endif
  }
}

extension RockYouApp {
  @CommandsBuilder
  private var appCommands: some Commands {
    CommandGroup(replacing: .newItem) {}

    CommandGroup(after: .windowArrangement) {
      Divider()
      OpenProtocolExplorerButton()
        .keyboardShortcut("P", modifiers: [.command, .option])
    }

    #if DEBUG
      CommandMenu("Debug") {
        Button("Inject Test Roku TV") {
          RokuDiscoveryService.shared.debugInjectTestRokuTV()
        }

        Button("Expire Test Roku TV") {
          RokuDiscoveryService.shared.debugExpireTestRokuTV()
        }

        Divider()

        Button("Generate Refracted DPad (Metal)") {
          Task { @MainActor in
            await DebugRefractedDPadGenerator.generateAndRevealInFinder()
          }
        }

        Divider()

        OpenDebugRenderWindowButton(title: "Render: Dome", windowId: "debug-render-dome")
        OpenDebugRenderWindowButton(title: "Render: Breaker", windowId: "debug-render-breaker")

        Divider()

        OpenDebugRenderWindowButton(
          title: "Playground: Dome",
          windowId: "debug-playground-dome"
        )
      }
    #endif
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
  private let mainWindowMinContentSize = CGSize(width: 240, height: 420)

  private var didBecomeMainObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    _ = notification

    // SwiftUI windows are created asynchronously; install once now and again when a window becomes main.
    installMinSizeForExistingWindows()
    didBecomeMainObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeMainNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let window = note.object as? NSWindow else { return }
      self?.installMinSizeIfMainRockYouWindow(window)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.installMinSizeForExistingWindows()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    _ = notification
    if let o = didBecomeMainObserver { NotificationCenter.default.removeObserver(o) }
    didBecomeMainObserver = nil
  }

  private func installMinSizeForExistingWindows() {
    for window in NSApp.windows {
      installMinSizeIfMainRockYouWindow(window)
    }
  }

  private func installMinSizeIfMainRockYouWindow(_ window: NSWindow) {
    // The SwiftUI `Window("RockYou", id: "main")` typically produces a window with title "RockYou".
    // Be conservative and don't apply to other tool windows (e.g. Protocol Explorer).
    guard window.title == "RockYou", !window.isSheet else { return }
    WindowMinSizeEnforcer.installIfNeeded(on: window, minContentSize: mainWindowMinContentSize)
  }

  func application(
    _ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
  ) {
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

// MARK: - NSWindowDelegate min-size clamp (with forwarding)

private final class WindowMinSizeEnforcer: NSObject, NSWindowDelegate {
  let minContentSize: CGSize
  private weak var forwarding: NSObject?
  private static var associatedKey: UInt8 = 0

  static func installIfNeeded(on window: NSWindow, minContentSize: CGSize) {
    // `NSWindow.delegate` is not a strong reference; retain our enforcer by associating it
    // with the window object itself.
    if let existing = objc_getAssociatedObject(window, &Self.associatedKey)
      as? WindowMinSizeEnforcer,
      existing.minContentSize == minContentSize,
      window.delegate === existing
    {
      // Still update these in case SwiftUI reset them.
      applyMinimumSizes(to: window, minContentSize: minContentSize)
      return
    }

    let forwarding = window.delegate as? NSObject
    let enforcer = WindowMinSizeEnforcer(minContentSize: minContentSize, forwardingTo: forwarding)
    objc_setAssociatedObject(
      window, &Self.associatedKey, enforcer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    window.delegate = enforcer

    applyMinimumSizes(to: window, minContentSize: minContentSize)
  }

  private static func applyMinimumSizes(to window: NSWindow, minContentSize: CGSize) {
    if window.contentMinSize != minContentSize {
      window.contentMinSize = minContentSize
    }

    let minFrameSize = minFrameSize(for: window, minContentSize: minContentSize)
    if window.minSize.width < minFrameSize.width || window.minSize.height < minFrameSize.height {
      window.minSize = NSSize(
        width: max(window.minSize.width, minFrameSize.width),
        height: max(window.minSize.height, minFrameSize.height)
      )
    }
  }

  private static func minFrameSize(for window: NSWindow, minContentSize: CGSize) -> NSSize {
    window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
  }

  init(minContentSize: CGSize, forwardingTo forwarding: NSObject?) {
    self.minContentSize = minContentSize
    self.forwarding = forwarding
    super.init()
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let minFrameSize = Self.minFrameSize(for: sender, minContentSize: minContentSize)
    let clamped = NSSize(
      width: max(frameSize.width, minFrameSize.width),
      height: max(frameSize.height, minFrameSize.height))

    return clamped
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    forwarding
  }

  override func responds(to aSelector: Selector!) -> Bool {
    if super.responds(to: aSelector) { return true }
    return forwarding?.responds(to: aSelector) ?? false
  }
}
