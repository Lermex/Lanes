import Foundation
import GitCore
import Highlighting
import SwiftUI

struct DiffPresentation: Sendable {
  struct Key: Hashable, Sendable {
    let source: DiffSource
    let fileIdentity: Int
    let themeName: String

    init(source: DiffSource, file: FileDiff, theme: SyntaxTheme) {
      self.source = source
      self.fileIdentity = file.hashValue
      self.themeName = theme.name
    }

    var isImmutable: Bool {
      if case .commitFile = source { return true }
      return false
    }
  }

  enum Row: Identifiable, Sendable {
    case hunkHeader(Hunk)
    case line(hunk: Hunk, line: DiffLine, text: AttributedString)

    var id: String {
      switch self {
      case .hunkHeader(let hunk): "h\(hunk.index)"
      case .line(let hunk, let line, _): "h\(hunk.index)l\(line.index)"
      }
    }
  }

  let key: Key
  let rows: [Row]
  let isHighlighted: Bool

  static func plain(source: DiffSource, file: FileDiff, theme: SyntaxTheme) -> DiffPresentation {
    build(key: Key(source: source, file: file, theme: theme), file: file, oldText: nil, newText: nil, theme: theme, highlight: false)
  }

  static func build(
    key: Key, file: FileDiff, oldText: String?, newText: String?, theme: SyntaxTheme, highlight: Bool = true
  ) -> DiffPresentation {
    let grammar = highlight ? LanguageRegistry.grammar(forPath: file.path) : nil
    let oldHighlights = zip(grammar, oldText).map { Highlighter.highlight($1, grammar: $0) }
    let newHighlights = zip(grammar, newText).map { Highlighter.highlight($1, grammar: $0) }
    let rows = file.hunks.flatMap { hunk -> [Row] in
      [.hunkHeader(hunk)] + hunk.lines.map { line in
        let runs: [StyledRun] =
          switch line.kind {
          case .removed: line.oldLineNumber.flatMap { oldHighlights?.runs(forLine: $0 - 1) } ?? []
          case .added, .context: line.newLineNumber.flatMap { newHighlights?.runs(forLine: $0 - 1) } ?? []
          case .noNewline: []
          }
        return .line(hunk: hunk, line: line, text: attributed(line.text, runs: runs, theme: theme))
      }
    }
    return DiffPresentation(key: key, rows: rows, isHighlighted: grammar != nil && (oldHighlights != nil || newHighlights != nil))
  }

  private static func attributed(_ text: String, runs: [StyledRun], theme: SyntaxTheme) -> AttributedString {
    let storage = text as NSString
    var result = AttributedString()
    var cursor = 0
    for run in runs where run.range.lowerBound >= cursor && run.range.upperBound <= storage.length {
      if run.range.lowerBound > cursor {
        result.append(piece(storage, cursor..<run.range.lowerBound, style: nil))
      }
      result.append(piece(storage, run.range, style: theme.style(for: run.scope)))
      cursor = run.range.upperBound
    }
    if cursor < storage.length {
      result.append(piece(storage, cursor..<storage.length, style: nil))
    }
    return result
  }

  private static func piece(_ storage: NSString, _ range: Range<Int>, style: SyntaxStyle?) -> AttributedString {
    let text = storage.substring(with: NSRange(range)).replacingOccurrences(of: "\t", with: "    ")
    var container = AttributeContainer()
    if let color = style?.color {
      container.foregroundColor = Theme.color(color)
    }
    if style?.bold == true {
      container.inlinePresentationIntent = .stronglyEmphasized
    } else if style?.italic == true {
      container.inlinePresentationIntent = .emphasized
    }
    return AttributedString(text, attributes: container)
  }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
  guard let a, let b else { return nil }
  return (a, b)
}
