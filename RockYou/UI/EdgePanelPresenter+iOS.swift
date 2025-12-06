import SwiftUI
import UIKit

enum EdgePanelAnchor: Sendable {
  case leading
  case trailing
  case top
  case bottom
}

struct EdgePanelPresenter<PanelContent: View>: UIViewControllerRepresentable {
  @Binding var isPresented: Bool
  let anchor: EdgePanelAnchor
  let preferredWidth: CGFloat
  let preferredHeight: CGFloat
  let allowsTapToDismiss: Bool
  let panelContent: () -> PanelContent

  func makeUIViewController(context: Context) -> UIViewController {
    let controller = UIViewController()
    controller.view.backgroundColor = .clear
    controller.definesPresentationContext = true
    return controller
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    context.coordinator.anchor = anchor
    context.coordinator.preferredWidth = preferredWidth
    context.coordinator.preferredHeight = preferredHeight
    context.coordinator.allowsTapToDismiss = allowsTapToDismiss

    if isPresented {
      context.coordinator.presentIfNeeded(
        from: uiViewController, content: panelContent(), isPresented: $isPresented)
    } else {
      context.coordinator.dismissIfNeeded()
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, UIViewControllerTransitioningDelegate,
    UIAdaptivePresentationControllerDelegate
  {
    var anchor: EdgePanelAnchor = .trailing
    var preferredWidth: CGFloat = 380
    var preferredHeight: CGFloat = 520
    var allowsTapToDismiss: Bool = true

    private weak var presentingViewController: UIViewController?
    private weak var presentedViewController: UIViewController?
    private var isPresentedBinding: Binding<Bool>?

    func presentIfNeeded<Content: View>(
      from viewController: UIViewController,
      content: Content,
      isPresented: Binding<Bool>
    ) {
      guard presentedViewController == nil else { return }
      presentingViewController = viewController
      isPresentedBinding = isPresented

      let host = UIHostingController(rootView: content)
      host.view.backgroundColor = .clear
      host.modalPresentationStyle = .custom
      host.transitioningDelegate = self
      host.presentationController?.delegate = self
      presentedViewController = host

      viewController.present(host, animated: true)
    }

    func dismissIfNeeded() {
      guard let presentedViewController else { return }
      guard !presentedViewController.isBeingDismissed else { return }
      presentedViewController.dismiss(animated: true)
      // `presentationControllerDidDismiss` clears `presentedViewController` and updates the binding.
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
      presentedViewController = nil
      if isPresentedBinding?.wrappedValue == true {
        isPresentedBinding?.wrappedValue = false
      }
      presentingViewController = nil
      isPresentedBinding = nil
    }

    func presentationController(
      _ controller: UIPresentationController,
      animationControllerForPresented presented: UIViewController,
      presenting: UIViewController,
      source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
      EdgePanelTransition(isPresenting: true, anchor: anchor)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
      EdgePanelTransition(isPresenting: false, anchor: anchor)
    }

    func presentationController(
      forPresented presented: UIViewController,
      presenting: UIViewController?,
      source: UIViewController
    ) -> UIPresentationController? {
      EdgePanelPresentationController(
        presentedViewController: presented,
        presenting: presenting ?? source,
        anchor: anchor,
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight,
        allowsTapToDismiss: allowsTapToDismiss
      )
    }

    func presentationController(_ controller: UIPresentationController, shouldDismiss: Bool) -> Bool {
      allowsTapToDismiss
    }

    func presentationController(
      _ controller: UIPresentationController,
      willPresentWithAdaptiveStyle style: UIModalPresentationStyle,
      transitionCoordinator: UIViewControllerTransitionCoordinator?
    ) {
      // no-op
    }
  }
}

// MARK: - View convenience

extension View {
  func edgePanel<PanelContent: View>(
    isPresented: Binding<Bool>,
    anchor: EdgePanelAnchor = .trailing,
    preferredWidth: CGFloat = 380,
    preferredHeight: CGFloat = 520,
    allowsTapToDismiss: Bool = true,
    @ViewBuilder content: @escaping () -> PanelContent
  ) -> some View {
    background(
      EdgePanelPresenter(
        isPresented: isPresented,
        anchor: anchor,
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight,
        allowsTapToDismiss: allowsTapToDismiss,
        panelContent: content
      )
    )
  }
}

// MARK: - Presentation controller

private final class EdgePanelPresentationController: UIPresentationController {
  private let anchor: EdgePanelAnchor
  private let preferredWidth: CGFloat
  private let preferredHeight: CGFloat
  private let allowsTapToDismiss: Bool

  private lazy var dimmingView: UIView = {
    let v = UIView()
    v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    v.alpha = 0
    if allowsTapToDismiss {
      let tap = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop))
      v.addGestureRecognizer(tap)
    }
    return v
  }()

  init(
    presentedViewController: UIViewController,
    presenting presentingViewController: UIViewController?,
    anchor: EdgePanelAnchor,
    preferredWidth: CGFloat,
    preferredHeight: CGFloat,
    allowsTapToDismiss: Bool
  ) {
    self.anchor = anchor
    self.preferredWidth = preferredWidth
    self.preferredHeight = preferredHeight
    self.allowsTapToDismiss = allowsTapToDismiss
    super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
  }

  override func presentationTransitionWillBegin() {
    guard let containerView else { return }
    dimmingView.frame = containerView.bounds
    containerView.insertSubview(dimmingView, at: 0)

    presentedViewController.transitionCoordinator?.animate { _ in
      self.dimmingView.alpha = 1
    }
  }

  override func dismissalTransitionWillBegin() {
    presentedViewController.transitionCoordinator?.animate { _ in
      self.dimmingView.alpha = 0
    }
  }

  override func dismissalTransitionDidEnd(_ completed: Bool) {
    if completed {
      dimmingView.removeFromSuperview()
    }
  }

  override func containerViewDidLayoutSubviews() {
    super.containerViewDidLayoutSubviews()
    dimmingView.frame = containerView?.bounds ?? .zero
    presentedView?.frame = frameOfPresentedViewInContainerView
  }

  override var frameOfPresentedViewInContainerView: CGRect {
    guard let containerView else { return .zero }
    let bounds = containerView.bounds.inset(by: containerView.safeAreaInsets)

    let width = min(preferredWidth, bounds.width)
    let height = min(preferredHeight, bounds.height)
    let y = bounds.minY + (bounds.height - height) / 2

    switch anchor {
    case .trailing:
      return CGRect(x: bounds.maxX - width, y: y, width: width, height: height)
    case .leading:
      return CGRect(x: bounds.minX, y: y, width: width, height: height)
    case .top:
      return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height)
    case .bottom:
      return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }
  }

  @objc private func didTapBackdrop() {
    presentedViewController.dismiss(animated: true)
  }
}

// MARK: - Transition

private final class EdgePanelTransition: NSObject, UIViewControllerAnimatedTransitioning {
  private let isPresenting: Bool
  private let anchor: EdgePanelAnchor

  init(isPresenting: Bool, anchor: EdgePanelAnchor) {
    self.isPresenting = isPresenting
    self.anchor = anchor
  }

  func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
    0.25
  }

  func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
    let key: UITransitionContextViewKey = isPresenting ? .to : .from
    guard let view = transitionContext.view(forKey: key) else {
      transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
      return
    }

    let container = transitionContext.containerView
    let duration = transitionDuration(using: transitionContext)

    if isPresenting {
      container.addSubview(view)
    }

    let finalFrame = isPresenting
      ? transitionContext.finalFrame(for: transitionContext.viewController(forKey: .to)!)
      : transitionContext.initialFrame(for: transitionContext.viewController(forKey: .from)!)

    var startFrame = finalFrame
    var endFrame = finalFrame

    func offsetFrame(_ frame: CGRect, by delta: CGFloat) -> CGRect {
      switch anchor {
      case .trailing:
        return frame.offsetBy(dx: delta, dy: 0)
      case .leading:
        return frame.offsetBy(dx: -delta, dy: 0)
      case .top:
        return frame.offsetBy(dx: 0, dy: -delta)
      case .bottom:
        return frame.offsetBy(dx: 0, dy: delta)
      }
    }

    let delta: CGFloat = (anchor == .top || anchor == .bottom) ? finalFrame.height : finalFrame.width

    if isPresenting {
      startFrame = offsetFrame(finalFrame, by: delta)
      endFrame = finalFrame
      view.frame = startFrame
    } else {
      startFrame = finalFrame
      endFrame = offsetFrame(finalFrame, by: delta)
    }

    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.curveEaseInOut]
    ) {
      view.frame = endFrame
    } completion: { finished in
      if !self.isPresenting && finished {
        view.removeFromSuperview()
      }
      transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
    }
  }
}
