//
//  ContentView.swift
//  RockYou Watch App
//
//  Gesture-based Roku remote with swipe D-pad and crown volume.
//  See UX-Design.md for design rationale.
//

import SwiftUI
import WatchKit

// MARK: - Remote Pages

enum RemotePage: Int, CaseIterable, Identifiable {
  case quickActions = 0
  case nav = 1
  case media = 2

  var id: Int { rawValue }

  var headerStyle: HeaderStyle {
    switch self {
    case .quickActions: return .tall
    default: return .compact
    }
  }

  enum HeaderStyle {
    case tall, compact
  }
}

// MARK: - Content View

struct ContentView: View {
  @StateObject private var connectivity = ConnectivityManager.shared
  @State private var settings = WatchAppSettings.shared
  @State private var showingTVSelector = false
  @State private var currentPage: RemotePage = .quickActions
  @State private var showingAppWheel = false
  @State private var slideDirection: SlideDirection = .forward
  @State private var lastVolumeAction: Date = .distantPast
  @State private var didApplyLaunchScreen = false

  enum SlideDirection {
    case forward, backward
  }

  var body: some View {
    VStack(spacing: 0) {
      if connectivity.selectedDevice != nil {
        HStack {
          tvSelectorHeader
          Spacer()
        }
        .padding(.top, 15)
        .padding(.horizontal, 8)
      }

      GeometryReader { geometry in
        ZStack {
          if connectivity.selectedDevice == nil {
            if connectivity.isPhoneReachable {
              noDeviceView
            } else {
              disconnectedView
            }
          } else {
            pageContent
              .id(currentPage)
              .transition(slideTransition)
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .animation(.easeInOut(duration: 0.25), value: currentPage)
      }
    }
    .ignoresSafeArea(edges: [.top, .bottom])
    .background(Color.black)
    .onOpenURL { url in
      guard let link = DeepLink(url: url) else { return }
      handleDeepLink(link)
    }
    .overlay {
      TooltipOverlayView()
      SweepOverlayView()
    }
    .sheet(isPresented: $showingTVSelector) {
      TVSelectorView(connectivity: connectivity, isPresented: $showingTVSelector)
    }
    .sheet(
      isPresented: Binding(
        get: { showingAppWheel },
        set: { newValue in
          if !newValue {
            TooltipManager.shared.dismiss(immediately: true)
          }
          showingAppWheel = newValue
        }
      )
    ) {
      AppGridView(
        apps: connectivity.apps,
        deviceId: connectivity.selectedDeviceId ?? "",
        onSelect: { app in
          WKInterfaceDevice.current().play(.click)
          connectivity.launchApp(app.id)
          showingAppWheel = false
        },
        isPresented: Binding(
          get: { showingAppWheel },
          set: { newValue in
            if !newValue {
              TooltipManager.shared.dismiss(immediately: true)
            }
            showingAppWheel = newValue
          }
        )
      )
    }
    .environment(\.onSwipeLeft, goToNextPage)
    .environment(\.onSwipeRight, goToPreviousPage)
    .onAppear {
      applyLaunchScreenIfNeeded()
    }
    .onChange(of: connectivity.selectedDeviceId) { _, _ in
      applyLaunchScreenIfNeeded()
    }
    .onChange(of: currentPage) { _, newValue in
      UserDefaults.standard.set(newValue.rawValue, forKey: "lastWatchRemotePage")
    }
  }

  @MainActor
  private func handleDeepLink(_ link: DeepLink) {
    switch link {
    case .selectDevice(let deviceId, let page):
      if connectivity.devices.contains(where: { $0.id == deviceId }) {
        connectivity.selectDevice(id: deviceId)
      }
      if let page {
        switch page.lowercased() {
        case "quick", "quickactions":
          slideDirection = .backward
          currentPage = .quickActions
        case "nav":
          slideDirection = .forward
          currentPage = .nav
        case "media":
          slideDirection = .forward
          currentPage = .media
        default:
          break
        }
      }
    }
  }

  private func applyLaunchScreenIfNeeded() {
    guard !didApplyLaunchScreen else { return }
    guard connectivity.selectedDeviceId != nil else { return }

    let launchScreen = settings.watchLaunchScreen

    if settings.watchAlwaysLaunchToMedia,
       let deviceId = connectivity.selectedDeviceId
    {
      let state = connectivity.deviceState(for: deviceId)
      if state.mediaState != .idle {
        currentPage = .media
        didApplyLaunchScreen = true
        return
      }
    }

    switch launchScreen {
    case .home:
      currentPage = .quickActions
    case .navigation:
      currentPage = .nav
    case .playback:
      currentPage = .media
    case .mru:
      let raw = UserDefaults.standard.integer(forKey: "lastWatchRemotePage")
      currentPage = RemotePage(rawValue: raw) ?? .quickActions
    }

    didApplyLaunchScreen = true
  }

  // MARK: - Header

  private var tvSelectorHeader: some View {
    Button {
      showingTVSelector = true
    } label: {
      HStack(spacing: 4) {
        Circle()
          .fill(statusColor)
          .frame(width: 6, height: 6)
        Text(connectivity.selectedDevice?.name ?? "Select TV")
          .font(.system(size: AppFontSize.caption, weight: .medium))
          .foregroundStyle(.white)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: AppFontSize.tiny, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(Color.white.opacity(AppOpacity.subtle))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .padding(.top, 2)
    .padding(.bottom, 2)
  }

  // MARK: - Page Content

  @ViewBuilder
  private var pageContent: some View {
    switch currentPage {
    case .quickActions:
      QuickActionsPage(
        pageCount: RemotePage.allCases.count,
        currentPage: currentPage.rawValue,
        hardwareControlsAvailable: connectivity.hardwareControlsAvailable,
        onAction: sendAction,
        onAppsPressed: {
          showingAppWheel = true
          connectivity.requestApps()
        },
        onCrownChange: handleCrownChange,
        onSwipeLeft: goToNextPage,
        onSwipeRight: goToPreviousPage,
        onPageTap: goToPage
      )

    case .nav:
      NavPage(
        pageCount: RemotePage.allCases.count,
        currentPage: currentPage.rawValue,
        apps: connectivity.apps,
        deviceId: connectivity.selectedDeviceId,
        onAction: sendAction,
        onLaunchApp: { app in
          WKInterfaceDevice.current().play(.click)
          connectivity.launchApp(app.id)
        },
        onCrownChange: handleCrownChange,
        onSwipeLeft: goToNextPage,
        onSwipeRight: goToPreviousPage,
        onPageTap: goToPage,
        onAppear: { connectivity.requestApps() }
      )

    case .media:
      MediaPage(
        pageCount: RemotePage.allCases.count,
        currentPage: currentPage.rawValue,
        hardwareControlsAvailable: connectivity.hardwareControlsAvailable,
        onAction: sendAction,
        onCrownChange: handleCrownChange,
        onSwipeLeft: goToNextPage,
        onSwipeRight: goToPreviousPage,
        onPageTap: goToPage
      )
    }
  }

  private var slideTransition: AnyTransition {
    switch slideDirection {
    case .forward:
      return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    case .backward:
      return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }
  }

  // MARK: - Page Navigation

  private func goToNextPage() {
    guard let nextIndex = RemotePage(rawValue: currentPage.rawValue + 1) else { return }
    WKInterfaceDevice.current().play(.click)
    slideDirection = .forward
    withAnimation(.easeInOut(duration: 0.25)) {
      currentPage = nextIndex
    }
  }

  private func goToPreviousPage() {
    guard let prevIndex = RemotePage(rawValue: currentPage.rawValue - 1) else { return }
    WKInterfaceDevice.current().play(.click)
    slideDirection = .backward
    withAnimation(.easeInOut(duration: 0.25)) {
      currentPage = prevIndex
    }
  }

  private func goToPage(_ index: Int) {
    guard let targetPage = RemotePage(rawValue: index) else { return }
    WKInterfaceDevice.current().play(.click)
    slideDirection = index > currentPage.rawValue ? .forward : .backward
    withAnimation(.easeInOut(duration: 0.25)) {
      currentPage = targetPage
    }
  }

  // MARK: - Crown Volume

  private func handleCrownChange(from oldValue: Double, to newValue: Double) {
    guard connectivity.hardwareControlsAvailable else { return }
    let now = Date()
    guard now.timeIntervalSince(lastVolumeAction) > 0.1 else { return }

    let delta = newValue - oldValue
    if delta > 2 {
      sendAction(.volumeUp)
      lastVolumeAction = now
    } else if delta < -2 {
      sendAction(.volumeDown)
      lastVolumeAction = now
    }
  }

  // MARK: - Actions

  private func sendAction(_ action: RemoteAction) {
    WKInterfaceDevice.current().play(.click)
    connectivity.send(action: action)
  }

  // MARK: - Status

  private var statusColor: Color {
    if !connectivity.isPhoneReachable {
      return .gray
    }
    guard let deviceId = connectivity.selectedDeviceId else {
      return .orange
    }
    return DeviceStateManager.shared.state(for: deviceId).powerMode.statusColor
  }

  // MARK: - No Device View

  private var noDeviceView: some View {
    VStack(spacing: 16) {
      Image(systemName: "tv")
        .font(.system(size: AppFontSize.iconMedium))
        .foregroundStyle(rokuPurple)

      Text("No TV Selected")
        .font(.headline)
        .foregroundStyle(.white)

      Text("Open RockYou on iPhone to discover TVs")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

      Button {
        connectivity.requestDevices()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
          .font(.caption)
      }
      .buttonStyle(.bordered)
      .tint(rokuPurple)
    }
    .padding()
  }

  // MARK: - Disconnected View

  private var disconnectedView: some View {
    VStack(spacing: 16) {
      Image(systemName: "iphone.slash")
        .font(.system(size: AppFontSize.iconMedium))
        .foregroundStyle(rokuPurple)

      Text("iPhone Unavailable")
        .font(.headline)
        .foregroundStyle(.white)

      Text("Open RockYou on your iPhone to sync TV list")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .padding()
  }
}

// MARK: - TV Selector View

private struct TVSelectorView: View {
  @ObservedObject var connectivity: ConnectivityManager
  @Binding var isPresented: Bool

  var body: some View {
    TVSelectorList(
      items: selectorItems,
      selectedId: connectivity.selectedDeviceId,
      isScanning: connectivity.isScanning,
      onSelect: { deviceId in
        connectivity.selectDevice(id: deviceId)
        isPresented = false
      },
      onRefresh: { connectivity.requestDevices() }
    )
    .navigationTitle("Select Device")
  }

  /// Build selector items from connectivity TVs
  private var selectorItems: [TVSelectorItem] {
    connectivity.devices.map { device in
      TVSelectorItem(
        id: device.id,
        selectionId: device.id,
        deviceType: device.isTV ? RokuDeviceType.tv : RokuDeviceType.streamingDevice,
        primaryName: device.name,
        secondaryName: {
          let kind = device.isTV ? "TV" : "Streamer"
          if let location = device.location, !location.isEmpty {
            return "\(location) • \(kind)"
          }
          return kind
        }()
      )
    }
  }
}

#Preview {
  ContentView()
}
