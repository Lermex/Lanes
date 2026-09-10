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

  @Test(arguments: [("lermex-intellij.json", "LermexIntellij", true), ("lermex-intellij-light.json", "LermexIntellij Light", false)])
  func bundledThemesResolveCommonScopes(file: String, name: String, isDark: Bool) throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Resources/Themes/\(file)")
    let theme = try #require(try ZedThemeFile.load(url).first)
    #expect(theme.name == name)
    #expect(theme.isDark == isDark)
    #expect(theme.editorBackground != nil && theme.addedBackground != nil && theme.removedBackground != nil)
    for scope in ["keyword", "keyword.return", "string", "number", "function.method", "type.builtin", "comment.doc", "property"] {
      #expect(theme.style(for: scope)?.color != nil, "no colour for \(scope)")
    }
  }
}
