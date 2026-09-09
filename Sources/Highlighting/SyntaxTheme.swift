import Foundation

public struct SyntaxStyle: Sendable, Hashable {
  public var color: UInt32?
  public var italic: Bool
  public var bold: Bool

  public init(color: UInt32?, italic: Bool = false, bold: Bool = false) {
    self.color = color
    self.italic = italic
    self.bold = bold
  }
}

public struct SyntaxTheme: Sendable, Hashable, Identifiable {
  public let name: String
  public let isDark: Bool
  public let styles: [String: SyntaxStyle]
  public let editorBackground: UInt32?
  public let editorForeground: UInt32?
  public let addedBackground: UInt32?
  public let removedBackground: UInt32?
  public let hunkHeaderBackground: UInt32?
  public let lineNumber: UInt32?
  public let addedMarker: UInt32?
  public let removedMarker: UInt32?

  public var id: String { name }

  public init(
    name: String, isDark: Bool, styles: [String: SyntaxStyle], editorBackground: UInt32? = nil, editorForeground: UInt32? = nil,
    addedBackground: UInt32? = nil, removedBackground: UInt32? = nil, hunkHeaderBackground: UInt32? = nil,
    lineNumber: UInt32? = nil, addedMarker: UInt32? = nil, removedMarker: UInt32? = nil
  ) {
    self.name = name
    self.isDark = isDark
    self.styles = styles
    self.editorBackground = editorBackground
    self.editorForeground = editorForeground
    self.addedBackground = addedBackground
    self.removedBackground = removedBackground
    self.hunkHeaderBackground = hunkHeaderBackground
    self.lineNumber = lineNumber
    self.addedMarker = addedMarker
    self.removedMarker = removedMarker
  }

  /// "keyword.return" falls back to "keyword" when the theme has no entry for the full scope.
  public func style(for scope: String) -> SyntaxStyle? {
    var components = scope.split(separator: ".").map(String.init)
    while !components.isEmpty {
      if let style = styles[components.joined(separator: ".")] { return style }
      components.removeLast()
    }
    return nil
  }
}

public enum ZedThemeFile {
  public static func load(_ url: URL) throws -> [SyntaxTheme] {
    let data = try Data(contentsOf: url)
    let family = try JSONDecoder().decode(Family.self, from: data)
    return family.themes.map { theme in
      let style = theme.style
      return SyntaxTheme(
        name: theme.name,
        isDark: theme.appearance.lowercased() == "dark",
        styles: style.syntax.compactMapValues { entry in
          SyntaxStyle(
            color: entry.color.flatMap(parseHex),
            italic: entry.font_style == "italic",
            bold: (entry.font_weight ?? 400) >= 600
          )
        },
        editorBackground: style.color("editor.background") ?? style.color("background"),
        editorForeground: style.color("editor.foreground") ?? style.color("text"),
        addedBackground: style.color("editor.diff_hunk.added.background") ?? style.color("created.background"),
        removedBackground: style.color("editor.diff_hunk.deleted.background") ?? style.color("deleted.background"),
        hunkHeaderBackground: style.color("editor.subheader.background") ?? style.color("elevated_surface.background"),
        lineNumber: style.color("editor.line_number"),
        addedMarker: style.color("created"),
        removedMarker: style.color("deleted")
      )
    }
  }

  static func parseHex(_ text: String) -> UInt32? {
    var hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
    guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
    if hex.count == 8 { hex.removeLast(2); return UInt32(hex, radix: 16) }
    return value
  }

  private struct Family: Decodable {
    let themes: [Theme]
  }

  private struct Theme: Decodable {
    let name: String
    let appearance: String
    let style: Style
  }

  private struct Style: Decodable {
    let syntax: [String: Entry]
    let colors: [String: String]

    func color(_ key: String) -> UInt32? { colors[key].flatMap(ZedThemeFile.parseHex) }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: DynamicKey.self)
      var colors: [String: String] = [:]
      var syntax: [String: Entry] = [:]
      for key in container.allKeys {
        if key.stringValue == "syntax" {
          syntax = (try? container.decode([String: Entry].self, forKey: key)) ?? [:]
        } else if let value = try? container.decode(String.self, forKey: key) {
          colors[key.stringValue] = value
        }
      }
      self.colors = colors
      self.syntax = syntax
    }
  }

  private struct Entry: Decodable {
    let color: String?
    let font_style: String?
    let font_weight: Int?
  }

  private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }
}

extension SyntaxTheme {
  public static let lanesDark = SyntaxTheme(
    name: "Lanes Dark", isDark: true,
    styles: [
      "keyword": SyntaxStyle(color: 0xFC5FA3), "variable.special": SyntaxStyle(color: 0xFC5FA3), "label": SyntaxStyle(color: 0xFC5FA3),
      "string": SyntaxStyle(color: 0xFC6A5D), "string.escape": SyntaxStyle(color: 0xFFA786),
      "comment": SyntaxStyle(color: 0x7F8C98), "function": SyntaxStyle(color: 0x67B7A4),
      "type": SyntaxStyle(color: 0x9FC4FF), "namespace": SyntaxStyle(color: 0x9FC4FF), "constructor": SyntaxStyle(color: 0x9FC4FF),
      "constant": SyntaxStyle(color: 0xD0BF69), "number": SyntaxStyle(color: 0xD0BF69), "boolean": SyntaxStyle(color: 0xD0BF69),
      "variable.parameter": SyntaxStyle(color: 0x5FB1DA), "property": SyntaxStyle(color: 0xB58CF2), "attribute": SyntaxStyle(color: 0xB58CF2),
      "operator": SyntaxStyle(color: 0xA0A6AD), "punctuation": SyntaxStyle(color: 0xA0A6AD),
      "tag": SyntaxStyle(color: 0x6FD3A8), "title": SyntaxStyle(color: 0x8AC7F5, bold: true),
      "emphasis": SyntaxStyle(color: nil, italic: true), "emphasis.strong": SyntaxStyle(color: nil, bold: true),
    ]
  )

  public static let lanesLight = SyntaxTheme(
    name: "Lanes Light", isDark: false,
    styles: [
      "keyword": SyntaxStyle(color: 0x9B2393), "variable.special": SyntaxStyle(color: 0x9B2393), "label": SyntaxStyle(color: 0x9B2393),
      "string": SyntaxStyle(color: 0xC41A16), "string.escape": SyntaxStyle(color: 0x8F2A1E),
      "comment": SyntaxStyle(color: 0x5D6C79), "function": SyntaxStyle(color: 0x326D74),
      "type": SyntaxStyle(color: 0x3E5A9A), "namespace": SyntaxStyle(color: 0x3E5A9A), "constructor": SyntaxStyle(color: 0x3E5A9A),
      "constant": SyntaxStyle(color: 0x1C00CF), "number": SyntaxStyle(color: 0x1C00CF), "boolean": SyntaxStyle(color: 0x1C00CF),
      "variable.parameter": SyntaxStyle(color: 0x0F68A0), "property": SyntaxStyle(color: 0x6C36A9), "attribute": SyntaxStyle(color: 0x6C36A9),
      "operator": SyntaxStyle(color: 0x6E7681), "punctuation": SyntaxStyle(color: 0x6E7681),
      "tag": SyntaxStyle(color: 0x0B6E4F), "title": SyntaxStyle(color: 0x0B4F79, bold: true),
      "emphasis": SyntaxStyle(color: nil, italic: true), "emphasis.strong": SyntaxStyle(color: nil, bold: true),
    ]
  )
}
