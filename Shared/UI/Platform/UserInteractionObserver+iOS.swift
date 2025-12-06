
import SwiftUI
import UIKit

/// Installs a non-interfering gesture recognizer on the hosting view's window to observe touches.
/// This is "observational" only: it does not cancel or delay touches for the rest of the app.
struct UserInteractionObserver: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    context.coordinator.installOnce(on: view)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.installOnce(on: uiView)
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    private var installed = false

    func installOnce(on view: UIView) {
      guard !installed else { return }
      installed = true

      // Install on the nearest window once available.
      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, let view else { return }
        guard let window = view.window else {
          self.installed = false
          return
        }

        let recognizer = TouchObserverGestureRecognizer { [weak self] in
          guard self != nil else { return }
          Task { @MainActor in
            UserInteractionTracker.shared.noteInteraction()
          }
        }
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

/// A gesture recognizer that never "recognizes" (so it won't compete), but reports touches.
private final class TouchObserverGestureRecognizer: UIGestureRecognizer {
  private let onTouch: () -> Void

  init(onTouch: @escaping () -> Void) {
    self.onTouch = onTouch
    super.init(target: nil, action: nil)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    onTouch()
    state = .failed  // immediately fail; we're purely observational
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    onTouch()
    state = .failed
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    state = .failed
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    state = .failed
  }
}
