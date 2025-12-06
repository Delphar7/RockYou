import SwiftUI

  #Preview("Watch Styles") {
    VStack(spacing: 12) {
      RemoteButton("chevron.left", action: {})
      RemoteButton("pause.fill", label: "Pause", action: {})
      RemoteButton(icon: "asterisk", action: {}, style: .circle)
    }
    .padding()
  }
