import SwiftUI

enum TunedInAppearance: String, CaseIterable, Identifiable {
  static let storageKey = "tunedIn.appearance.v2"
  static let defaultAppearance: TunedInAppearance = .light

  case system
  case light
  case dark

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var systemImage: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max.fill"
    case .dark: "moon.stars.fill"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
