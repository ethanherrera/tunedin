import SwiftUI

enum CommunityEventScoreBand: Equatable {
  case red
  case yellow
  case green

  init(score: Double) {
    if score >= 8 {
      self = .green
    } else if score >= 5 {
      self = .yellow
    } else {
      self = .red
    }
  }

  var accessibilityDescription: String {
    switch self {
    case .red: "low score"
    case .yellow: "middle score"
    case .green: "high score"
    }
  }

  var fill: Color {
    switch self {
    case .red: Color(red: 0.70, green: 0.14, blue: 0.11)
    case .yellow: Color(red: 0.95, green: 0.70, blue: 0.20)
    case .green: Color(red: 0.09, green: 0.50, blue: 0.27)
    }
  }

  var foreground: Color {
    switch self {
    case .yellow: TunedInDesign.ink
    case .red, .green: .white
    }
  }
}

struct CommunityEventScoreBadge: View {
  enum Size {
    case compact
    case standard
    case large
  }

  let score: Double
  var size = Size.standard

  var body: some View {
    let band = CommunityEventScoreBand(score: score)

    Text(score.formatted(.number.precision(.fractionLength(1))))
      .font(font)
      .monospacedDigit()
      .foregroundStyle(band.foreground)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(band.fill, in: Capsule())
      .accessibilityLabel(
        "\(score.formatted(.number.precision(.fractionLength(1)))), "
          + band.accessibilityDescription
      )
  }

  private var font: Font {
    switch size {
    case .compact: .caption.weight(.bold)
    case .standard: .headline.weight(.bold)
    case .large: .title2.weight(.bold)
    }
  }

  private var horizontalPadding: CGFloat {
    switch size {
    case .compact: 6
    case .standard: 8
    case .large: 10
    }
  }

  private var verticalPadding: CGFloat {
    switch size {
    case .compact: 3
    case .standard: 4
    case .large: 5
    }
  }
}
