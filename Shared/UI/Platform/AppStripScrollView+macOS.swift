//
//  AppStripScrollView+macOS.swift
//  RockYou (Shared)
//
//  macOS-specific scroll view wrapper for AppStrip that provides:
//  - Click-and-drag scrolling (including when starting on buttons)
//  - Vertical wheel to horizontal scroll conversion
//

  import SwiftUI
  import AppKit
  import QuartzCore

/// macOS implementation of the `AppStripScrollView`
  struct AppStripScrollView<Content: View>: View {
    let content: Content
    let axis: Axis.Set
    let direction: AppStripDirection
    let deviceId: String
    let onScrollGestureChanged: (Bool) -> Void

    // Force NSHostingView to re-diff when MRU ordering changes.
    // The NSViewRepresentable bridge can't detect closure-captured reordering
    // inside ForEach(0..<n, id: \.self), so we stamp the content with mruVersion.
    @ObservedObject private var cache = AppCacheManager.shared

    var body: some View {
      MacAppStripScrollView(
        content: content.id(cache.mruVersion).padding(.top, 2),
        axis: axis,
        direction: direction,
        deviceId: deviceId,
        onScrollGestureChanged: onScrollGestureChanged
      )
    }
  }

  protocol ScrollEventCoordinator: AnyObject {
    var axis: Axis.Set { get set }
    func handleScrollGestureChanged(_ active: Bool)
  }

  struct MacAppStripScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let axis: Axis.Set
    let direction: AppStripDirection
    let deviceId: String
    let onScrollGestureChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(
        axis: axis,
        direction: direction,
        deviceId: deviceId,
        onScrollGestureChanged: onScrollGestureChanged
      )
    }

    func makeNSView(context: Context) -> InterceptingScrollView {
      let scrollView = InterceptingScrollView()
      scrollView.coordinator = context.coordinator
      scrollView.autohidesScrollers = true
      scrollView.borderType = .noBorder
      scrollView.scrollerStyle = .overlay
      scrollView.drawsBackground = false
      // Host SwiftUI content (keep a stable documentView to avoid scroll position resets)
      let hostingView = NSHostingView(rootView: content)
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.documentView = hostingView
      context.coordinator.hostingView = hostingView

      configureScrollView(scrollView)

      context.coordinator.scrollView = scrollView
      return scrollView
    }

    func updateNSView(_ scrollView: InterceptingScrollView, context: Context) {
      // DO NOT replace documentView here (that resets scroll offset back to zero).
      // Just update the existing hosting view's rootView.
      if let existing = context.coordinator.hostingView {
        let preservedOrigin = scrollView.contentView.bounds.origin
        existing.rootView = content
        existing.invalidateIntrinsicContentSize()
        // Preserve scroll offset across content updates / state toggles.
        if scrollView.contentView.bounds.origin != preservedOrigin {
          scrollView.contentView.scroll(to: preservedOrigin)
        }
        // Reflect so scroller size stays correct when content size changes.
        scrollView.reflectScrolledClipView(scrollView.contentView)
      } else if let existing = scrollView.documentView as? NSHostingView<Content> {
        context.coordinator.hostingView = existing
        let preservedOrigin = scrollView.contentView.bounds.origin
        existing.rootView = content
        existing.invalidateIntrinsicContentSize()
        if scrollView.contentView.bounds.origin != preservedOrigin {
          scrollView.contentView.scroll(to: preservedOrigin)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }

      configureScrollView(scrollView)

      context.coordinator.scrollView = scrollView
      context.coordinator.axis = axis
    }

    private func configureScrollView(_ scrollView: InterceptingScrollView) {
      // Configure scroll direction
      if axis == .horizontal {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed
      } else {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
      }
    }

    final class Coordinator: NSObject, ScrollEventCoordinator {
      weak var scrollView: InterceptingScrollView?
      weak var hostingView: NSHostingView<Content>?
      var onScrollGestureChanged: (Bool) -> Void
      var axis: Axis.Set
      let direction: AppStripDirection
      let deviceId: String
      private var scrollIdleTask: DispatchWorkItem?

      init(
        axis: Axis.Set,
        direction: AppStripDirection,
        deviceId: String,
        onScrollGestureChanged: @escaping (Bool) -> Void
      ) {
        self.onScrollGestureChanged = onScrollGestureChanged
        self.axis = axis
        self.direction = direction
        self.deviceId = deviceId
      }

      func handleScrollGestureChanged(_ active: Bool) {
        emitScrollGestureChanged(active)
        if active { scheduleScrollEnd() }
      }

      private func scheduleScrollEnd() {
        scrollIdleTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
          self?.emitScrollGestureChanged(false)
        }
        scrollIdleTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
      }

      private func emitScrollGestureChanged(_ active: Bool) {
        Task { @MainActor in
          DebugBuild.run {
            Log.gestureTimeline(
              "AppStrip",
              "scrollGesture",
              [
                "platform": "macOS",
                "active": active ? "true" : "false",
                "deviceId": deviceId,
                "direction": direction == .horizontal ? "horizontal" : "vertical",
              ]
            )
          }
          onScrollGestureChanged(active)
        }
      }
    }
  }

  /// Custom NSScrollView that enables click-and-drag scrolling even when starting on buttons.
  final class InterceptingScrollView: NSScrollView {
    weak var coordinator: ScrollEventCoordinator?

    private var isDragging = false
    private var lastMouseLocation: NSPoint = .zero
    private var initialMouseLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 3.0
    private var eventMonitor: Any?
    private var mouseDownInWindow = false

    // Smoothness tuning
    private let scrollSensitivity: CGFloat = 0.6
    private var pendingScrollerReflect = false

    // Drag momentum (mouse "swipe" inertia)
    private struct DragSample {
      let t: CFTimeInterval
      let location: NSPoint
    }
    private var dragSamples: [DragSample] = []
    private var inertiaTimer: Timer?
    private var inertiaVelocity: CGFloat = 0  // points/sec in scroll axis (content space)
    private var lastInertiaTick: CFTimeInterval = 0
    private let inertiaMinVelocity: CGFloat = 120  // points/sec threshold to start inertia
    private let inertiaStopVelocity: CGFloat = 10  // stop when slow
    private let inertiaDecayPerSecond: CGFloat = 2.8  // higher = faster stop (exp decay)

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil { installEventMonitor() } else { removeEventMonitor() }
    }

    private func installEventMonitor() {
      guard eventMonitor == nil else { return }
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp,
      ]) {
        [weak self] event in
        guard let self = self else { return event }

        let locationInView = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(locationInView) else { return event }

        switch event.type {
        case .leftMouseDown:
          self.handleGlobalMouseDown(event)
          return event  // allow button press for clicks
        case .leftMouseDragged:
          self.handleGlobalMouseDragged(event)
          return self.isDragging ? nil : event
        case .leftMouseUp:
          // Important: decide whether to consume *before* handleGlobalMouseUp clears isDragging.
          let wasDragging = self.isDragging
          self.handleGlobalMouseUp(event)
          return wasDragging ? nil : event
        default:
          return event
        }
      }
    }

    private func removeEventMonitor() {
      if let monitor = eventMonitor {
        NSEvent.removeMonitor(monitor)
        eventMonitor = nil
      }
    }

    private func handleGlobalMouseDown(_ event: NSEvent) {
      stopInertia()
      let location = convert(event.locationInWindow, from: nil)
      initialMouseLocation = location
      lastMouseLocation = location
      mouseDownInWindow = true
      isDragging = false

      dragSamples.removeAll(keepingCapacity: true)
      dragSamples.append(DragSample(t: CACurrentMediaTime(), location: location))
    }

    private func handleGlobalMouseDragged(_ event: NSEvent) {
      guard mouseDownInWindow else { return }

      let location = convert(event.locationInWindow, from: nil)
      let deltaX = location.x - initialMouseLocation.x
      let deltaY = location.y - initialMouseLocation.y
      let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

      if !isDragging && distance > dragThreshold {
        isDragging = true
        coordinator?.handleScrollGestureChanged(true)
      }

      guard isDragging else { return }

      // Track recent samples for velocity estimation (keep last ~120ms)
      let now = CACurrentMediaTime()
      dragSamples.append(DragSample(t: now, location: location))
      let cutoff = now - 0.12
      if dragSamples.count > 8 || (dragSamples.first?.t ?? 0) < cutoff {
        dragSamples = dragSamples.filter { $0.t >= cutoff }
      }

      let clipView = contentView
      var newOrigin = clipView.bounds.origin

      if let coordinator = coordinator, coordinator.axis == .horizontal {
        let delta = (location.x - lastMouseLocation.x) * scrollSensitivity
        newOrigin.x -= delta
        if let doc = clipView.documentView {
          newOrigin.x = max(0, min(newOrigin.x, doc.bounds.width - clipView.bounds.width))
        }
      } else {
        let delta = (location.y - lastMouseLocation.y) * scrollSensitivity
        newOrigin.y -= delta
        if let doc = clipView.documentView {
          newOrigin.y = max(0, min(newOrigin.y, doc.bounds.height - clipView.bounds.height))
        }
      }

      // Optimized scrolling API
      clipView.scroll(to: newOrigin)

      // Keep scrollers synced without jank:
      // coalesce reflect calls to at most once per runloop (uses latest bounds.origin).
      scheduleScrollerReflect()

      lastMouseLocation = location
    }

    private func handleGlobalMouseUp(_ event: NSEvent) {
      mouseDownInWindow = false
      if isDragging {
        isDragging = false
        coordinator?.handleScrollGestureChanged(false)
        // Force a final sync at drag end so the bar never lags.
        reflectScrolledClipView(contentView)

        startInertiaIfNeeded()
      }
    }

    override func scrollWheel(with event: NSEvent) {
      // Wheel input should cancel inertia (feels natural and avoids double-scrolling).
      if inertiaTimer != nil { stopInertia() }

      guard let coordinator = coordinator else {
        super.scrollWheel(with: event)
        return
      }

      // Convert vertical wheel to horizontal when the strip is horizontal.
      if coordinator.axis == .horizontal && abs(event.deltaY) > abs(event.deltaX) {
        coordinator.handleScrollGestureChanged(true)

        let clipView = contentView
        var newOrigin = clipView.bounds.origin

        // Tuning: trackpads (precise deltas) already have momentum/velocity, so keep scale small.
        // Mouse wheels (coarse deltas) need a larger scale to feel responsive.
        let verticalDelta: CGFloat =
          event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let wheelScale: CGFloat = event.hasPreciseScrollingDeltas ? 1.5 : 30.0
        newOrigin.x -= verticalDelta * wheelScale * scrollSensitivity
        if let doc = clipView.documentView {
          newOrigin.x = max(0, min(newOrigin.x, doc.bounds.width - clipView.bounds.width))
        }

        clipView.scroll(to: newOrigin)
        scheduleScrollerReflect()
      } else {
        if abs(event.deltaX) > 0 || abs(event.deltaY) > 0 {
          coordinator.handleScrollGestureChanged(true)
        }
        super.scrollWheel(with: event)
      }
    }

    private func scheduleScrollerReflect() {
      guard !pendingScrollerReflect else { return }
      pendingScrollerReflect = true
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.pendingScrollerReflect = false
        self.reflectScrolledClipView(self.contentView)
      }
    }

    private func startInertiaIfNeeded() {
      guard let coordinator = coordinator else { return }
      guard dragSamples.count >= 2 else { return }

      guard let first = dragSamples.first, let last = dragSamples.last else {
        dragSamples.removeAll(keepingCapacity: true)
        return
      }
      let dt = max(0.001, last.t - first.t)

      let mouseDelta: CGFloat
      if coordinator.axis == .horizontal {
        mouseDelta = last.location.x - first.location.x
      } else {
        mouseDelta = last.location.y - first.location.y
      }

      // Convert mouse velocity to scroll velocity in content space.
      // Our scroll moves opposite of mouse movement (newOrigin -= delta).
      let v0 = -(mouseDelta / CGFloat(dt)) * scrollSensitivity

      guard abs(v0) >= inertiaMinVelocity else {
        dragSamples.removeAll(keepingCapacity: true)
        return
      }

      inertiaVelocity = v0
      lastInertiaTick = CACurrentMediaTime()

      // Run at ~60fps.
      inertiaTimer?.invalidate()
      inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
        [weak self] _ in
        self?.stepInertia()
      }
      // Ensure it continues during tracking.
      if let inertiaTimer {
        RunLoop.main.add(inertiaTimer, forMode: .common)
      }
      dragSamples.removeAll(keepingCapacity: true)
    }

    private func stepInertia() {
      guard let coordinator = coordinator else { stopInertia(); return }
      let now = CACurrentMediaTime()
      let dt = max(0.001, now - lastInertiaTick)
      lastInertiaTick = now

      guard abs(inertiaVelocity) > inertiaStopVelocity else {
        stopInertia()
        return
      }

      let clipView = contentView
      var newOrigin = clipView.bounds.origin

      if coordinator.axis == .horizontal {
        // inertiaVelocity is "origin delta per second" in content space.
        // Apply directly (same sign convention as drag scrolling).
        newOrigin.x += inertiaVelocity * CGFloat(dt)
        if let doc = clipView.documentView {
          let clamped = max(0, min(newOrigin.x, doc.bounds.width - clipView.bounds.width))
          if clamped != newOrigin.x {
            newOrigin.x = clamped
            // Hit an edge → stop.
            stopInertia()
          }
        }
      } else {
        newOrigin.y += inertiaVelocity * CGFloat(dt)
        if let doc = clipView.documentView {
          let clamped = max(0, min(newOrigin.y, doc.bounds.height - clipView.bounds.height))
          if clamped != newOrigin.y {
            newOrigin.y = clamped
            stopInertia()
          }
        }
      }

      clipView.scroll(to: newOrigin)
      scheduleScrollerReflect()

      // Exponential decay (frame-rate independent): v *= exp(-k * dt)
      let decay = exp(-inertiaDecayPerSecond * CGFloat(dt))
      inertiaVelocity *= decay
    }

    private func stopInertia() {
      inertiaTimer?.invalidate()
      inertiaTimer = nil
      inertiaVelocity = 0
      lastInertiaTick = 0
    }

    deinit {
      stopInertia()
      removeEventMonitor()
    }
  }
