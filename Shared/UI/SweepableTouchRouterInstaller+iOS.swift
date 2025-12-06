//
//  SweepableTouchRouterInstaller+iOS.swift
//  RockYou (Shared)
//
//  Bridges a SwiftUI view into the iOS SweepableTouchRouter.
//

import SwiftUI
import UIKit

@MainActor
struct SweepableTouchRouterInstaller: UIViewRepresentable {
  /// Fallback frame in SwiftUI `.global` space (best-effort only).
  /// The installer prefers measuring its own `UIView` frame in the window.
  var frame: CGRect
  var suppressed: Bool
  /// Debug label used by SweepableTouchRouter logs (safe in release; just empty).
  var debugLabel: String = ""

  let onBegan: () -> Void
  let onMoved: (CGFloat) -> Void
  let onEnded: (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onBegan: onBegan, onMoved: onMoved, onEnded: onEnded, debugLabel: debugLabel)
  }

  func makeUIView(context: Context) -> UIView {
    let view = RegistrationView(frame: .zero)
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.onWindowChange = { [weak coordinator = context.coordinator] window in
      coordinator?.setWindow(window)
    }
    // Keep the registered frame in sync even when SwiftUI moves views (e.g. scroll/reorder).
    // SwiftUI can re-layout without calling updateUIView on every animation/scroll tick.
    view.onLayout = { [weak coordinator = context.coordinator, weak view] in
      guard let coordinator, let view else { return }
      guard let window = view.window else { return }
      let windowFrame = view.convert(view.bounds, to: window)
      coordinator.updateFrame(windowFrame)
    }
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.updateCallbacks(onBegan: onBegan, onMoved: onMoved, onEnded: onEnded)
    context.coordinator.update(debugLabel: debugLabel)
    if let window = uiView.window {
      let windowFrame = uiView.convert(uiView.bounds, to: window)
      context.coordinator.update(frame: windowFrame, suppressed: suppressed)
    } else {
      context.coordinator.update(frame: frame, suppressed: suppressed)
    }
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    _ = uiView
    coordinator.unregister()
  }

  @MainActor
  final class Coordinator: NSObject, SweepableTouchTarget {
    private var onBegan: () -> Void
    private var onMoved: (CGFloat) -> Void
    private var onEnded: (Bool) -> Void

    private weak var window: UIWindow?
    private(set) var sweepableFrame: CGRect = .zero
    private(set) var sweepableSuppressed: Bool = false
    private(set) var sweepableDebugLabel: String

    init(
      onBegan: @escaping () -> Void,
      onMoved: @escaping (CGFloat) -> Void,
      onEnded: @escaping (Bool) -> Void,
      debugLabel: String
    ) {
      self.onBegan = onBegan
      self.onMoved = onMoved
      self.onEnded = onEnded
      self.sweepableDebugLabel = debugLabel
    }

    func updateCallbacks(
      onBegan: @escaping () -> Void,
      onMoved: @escaping (CGFloat) -> Void,
      onEnded: @escaping (Bool) -> Void
    ) {
      self.onBegan = onBegan
      self.onMoved = onMoved
      self.onEnded = onEnded
    }

    func update(frame: CGRect, suppressed: Bool) {
      self.sweepableFrame = frame
      self.sweepableSuppressed = suppressed
    }

    func update(debugLabel: String) {
      self.sweepableDebugLabel = debugLabel
    }

    func updateFrame(_ frame: CGRect) {
      self.sweepableFrame = frame
    }

    func unregister() {
      if let window {
        SweepableTouchRouter.shared(for: window).unregister(self)
      }
      window = nil
    }

    func setWindow(_ newWindow: UIWindow?) {
      if window === newWindow { return }
      unregister()
      guard let newWindow else { return }
      window = newWindow
      SweepableTouchRouter.shared(for: newWindow).register(self)
    }

    // MARK: - SweepableTouchTarget

    func sweepableTouchBegan() {
      onBegan()
    }

    func sweepableTouchMoved(distance: CGFloat) {
      onMoved(distance)
    }

    func sweepableTouchEnded(cancelled: Bool) {
      onEnded(cancelled)
    }
  }

  private final class RegistrationView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?
    var onLayout: (() -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      onWindowChange?(window)
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      onLayout?()
    }
  }
}
