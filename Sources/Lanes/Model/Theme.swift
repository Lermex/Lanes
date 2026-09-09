import AppKit
import Highlighting
import SwiftUI

enum Theme {
  static let codeFont = Font.system(size: 12, design: .monospaced)
  static let historyRowHeight: CGFloat = 26
  static let laneWidth: CGFloat = 14

  static let graphPalette: [Color] = [
    .blue, .orange, .green, .purple, .pink, .teal, .red, .indigo, .brown, .mint,
  ]

  static func graphColor(_ index: Int) -> Color {
    graphPalette[index % graphPalette.count]
  }

  static let addedLineBackground = adaptive(light: 0xE6FFEC, dark: 0x12261E)
  static let removedLineBackground = adaptive(light: 0xFFEBE9, dark: 0x2D1418)
  static let hunkHeaderBackground = adaptive(light: 0xDDF4FF, dark: 0x1A2A3A)
  static let addedMarker = adaptive(light: 0x1A7F37, dark: 0x3FB950)
  static let removedMarker = adaptive(light: 0xCF222E, dark: 0xF85149)

  static func color(_ hex: UInt32) -> Color { Color(nsColor: NSColor(hex: hex)) }

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: adaptiveNS(light: light, dark: dark))
  }

  private static func adaptiveNS(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return NSColor(hex: isDark ? dark : light)
    }
  }
}

extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
