import Foundation
import Testing
@testable import Highlighting

@Suite struct TypeScriptQueryTests {
  @Test func typeScriptInheritsJavaScriptHighlights() throws {
    let grammar = try #require(LanguageRegistry.grammar(for: .typescript))
    let highlighted = Highlighter.highlight("const retries: number = 3;\nreturn JSON.parse(raw);\n", grammar: grammar)
    let scopes = highlighted.lines.flatMap { $0.map(\.scope) }
    #expect(scopes.contains { $0.hasPrefix("keyword") })
    #expect(scopes.contains("number"))
    #expect(scopes.contains { $0.hasPrefix("type") })
    #expect(scopes.contains { $0.hasPrefix("function") })
  }

  @Test func bundledIntelliJThemeResolvesCommonScopes() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Resources/Themes/lermex-intellij.json")
    let theme = try #require(try ZedThemeFile.load(url).first)
    #expect(theme.name == "LermexIntellij")
    for scope in ["keyword", "keyword.return", "string", "number", "function.method", "type.builtin", "comment.doc", "property"] {
      #expect(theme.style(for: scope)?.color != nil, "no colour for \(scope)")
    }
  }
}
