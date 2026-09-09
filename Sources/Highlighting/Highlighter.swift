import Foundation
import SwiftTreeSitter

public struct StyledRun: Sendable, Hashable {
  public let range: Range<Int>
  public let scope: String

  public init(range: Range<Int>, scope: String) {
    self.range = range
    self.scope = scope
  }
}

public struct HighlightedText: Sendable {
  public let lines: [[StyledRun]]

  public func runs(forLine index: Int) -> [StyledRun] {
    lines.indices.contains(index) ? lines[index] : []
  }

  public static let empty = HighlightedText(lines: [])
}

public enum Highlighter {
  public static let maximumLength = 3_000_000

  public static func highlight(_ text: String, grammar: Grammar) -> HighlightedText {
    let storage = text as NSString
    guard storage.length > 0, storage.length <= maximumLength else { return .empty }
    let parser = Parser()
    guard (try? parser.setLanguage(grammar.language)) != nil, let tree = parser.parse(text) else { return .empty }
    var scopes = ScopeTable()
    let spans = collectSpans(text: text, tree: tree, query: grammar.highlights, scopes: &scopes)
    let painted = paint(spans, length: storage.length)
    return HighlightedText(lines: splitIntoLines(painted, storage: storage, scopes: scopes))
  }

  private struct ScopeTable {
    private(set) var names: [String] = []
    private var indices: [String: UInt16] = [:]

    mutating func index(of scope: String) -> UInt16 {
      if let existing = indices[scope] { return existing }
      let index = UInt16(names.count + 1)
      names.append(scope)
      indices[scope] = index
      return index
    }

    func name(at index: UInt16) -> String? { index == 0 ? nil : names[Int(index) - 1] }
  }

  private struct Span {
    let range: NSRange
    let patternIndex: Int
    let scope: UInt16
  }

  private static func collectSpans(text: String, tree: MutableTree, query: Query, scopes: inout ScopeTable) -> [Span] {
    var matches = query.execute(in: tree).resolve(with: Predicate.Context(string: text))
    var byRange: [NSRange: Span] = [:]
    while let match = matches.next() {
      for capture in match.captures {
        guard let name = capture.name, let scope = ScopeNormalizer.normalize(name) else { continue }
        let span = Span(range: capture.range, patternIndex: capture.patternIndex, scope: scopes.index(of: scope))
        if let existing = byRange[span.range], existing.patternIndex >= span.patternIndex { continue }
        byRange[span.range] = span
      }
    }
    return byRange.values.sorted { lhs, rhs in
      lhs.range.location != rhs.range.location
        ? lhs.range.location < rhs.range.location
        : lhs.range.length > rhs.range.length
    }
  }

  private static func paint(_ spans: [Span], length: Int) -> [UInt16] {
    var scopes = [UInt16](repeating: 0, count: length)
    for span in spans {
      let lower = max(0, span.range.location)
      let upper = min(length, span.range.location + span.range.length)
      guard lower < upper else { continue }
      scopes.replaceSubrange(lower..<upper, with: repeatElement(span.scope, count: upper - lower))
    }
    return scopes
  }

  private static func splitIntoLines(_ kinds: [UInt16], storage: NSString, scopes: ScopeTable) -> [[StyledRun]] {
    var lines: [[StyledRun]] = []
    var position = 0
    while position < storage.length {
      var contentEnd = 0
      var lineEnd = 0
      storage.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: position, length: 0))
      lines.append(runs(in: kinds, from: position, to: contentEnd, scopes: scopes))
      position = lineEnd
    }
    return lines
  }

  private static func runs(in kinds: [UInt16], from start: Int, to end: Int, scopes: ScopeTable) -> [StyledRun] {
    var result: [StyledRun] = []
    var runStart = start
    var index = start
    while index < end {
      let kind = kinds[index]
      var next = index + 1
      while next < end, kinds[next] == kind { next += 1 }
      if let scope = scopes.name(at: kind) {
        result.append(StyledRun(range: (runStart - start)..<(next - start), scope: scope))
      }
      runStart = next
      index = next
    }
    return result
  }
}
