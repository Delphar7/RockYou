import SwiftUI

#Preview("iOS Styles") {
  VStack(spacing: 20) {
    HStack(spacing: 16) {
      RemoteButton("chevron.left", action: {})
      RemoteButton("house.fill", action: {})
      RemoteButton("gearshape.fill", action: {})
    }
    HStack(spacing: 14) {
      CircleKeyButton(systemName: "arrow.left", size: 64, baseColor: rokuDarkPurple) {}
      OKKeyButton(size: 84) {}
      CircleKeyButton(systemName: "arrow.right", size: 64, baseColor: rokuDarkPurple) {}
    }
  }
  .padding()
  .background(Color.black)
}
