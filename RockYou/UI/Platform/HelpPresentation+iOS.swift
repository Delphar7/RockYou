import SafariServices
import SwiftUI

extension View {
  /// Presents the RockYou docs in-app on iOS (SFSafariViewController).
  func platformHelpPresentation(isPresented: Binding<Bool>, url: URL) -> some View {
    sheet(isPresented: isPresented) {
      SafariView(url: url)
        .ignoresSafeArea()
    }
  }
}

private struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let vc = SFSafariViewController(url: url)
    vc.dismissButtonStyle = .close
    return vc
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    _ = uiViewController
    _ = context
  }
}
