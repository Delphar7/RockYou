import SwiftUI

extension View {
  /// Presents the RockYou docs on macOS by opening the default browser.
  func platformHelpPresentation(isPresented: Binding<Bool>, url: URL) -> some View {
    modifier(MacHelpPresentationModifier(isPresented: isPresented, url: url))
  }
}

private struct MacHelpPresentationModifier: ViewModifier {
  @Environment(\.openURL) private var openURL
  @Binding var isPresented: Bool
  let url: URL

  func body(content: Content) -> some View {
    content
      .onChange(of: isPresented) { _, newValue in
        guard newValue else { return }
        openURL(url)
        isPresented = false
      }
  }
}
