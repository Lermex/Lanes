import Foundation
import Testing
@testable import Highlighting

@Suite struct ScopeNormalizerTests {
  @Test func mapsCaptureNamesOntoZedScopes() {
    #expect(ScopeNormalizer.normalize("keyword.return") == "keyword.return")
    #expect(ScopeNormalizer.normalize("conditional") == "keyword.conditional")
    #expect(ScopeNormalizer.normalize("string.escape") == "string.escape")
    #expect(ScopeNormalizer.normalize("variable.builtin") == "variable.special")
    #expect(ScopeNormalizer.normalize("function.call") == "function.call")
    #expect(ScopeNormalizer.normalize("method.call") == "function.method")
    #expect(ScopeNormalizer.normalize("comment.documentation") == "comment.doc")
    #expect(ScopeNormalizer.normalize("_function") == nil)
    #expect(ScopeNormalizer.normalize("spell") == nil)
  }
}

@Suite struct SyntaxThemeTests {
  @Test func fallsBackToShorterScopes() {
    let theme = SyntaxTheme(name: "t", isDark: true, styles: ["keyword": SyntaxStyle(color: 1), "string.escape": SyntaxStyle(color: 2)])
    #expect(theme.style(for: "keyword.return")?.color == 1)
    #expect(theme.style(for: "string.escape")?.color == 2)
    #expect(theme.style(for: "string") == nil)
  }

  @Test func loadsZedThemeFiles() throws {
    let json = """
      {"name": "Fam", "author": "x", "themes": [{"name": "Dark One", "appearance": "dark", "style": {
        "editor.background": "#1e1e1e", "editor.foreground": "#e3e3e3", "created.background": "#294436",
        "editor.diff_hunk.deleted.background": "#484a4a", "border": null,
        "syntax": {"keyword": {"color": "#82c1bf", "font_style": null, "font_weight": null},
                   "emphasis.strong": {"color": "#e3e3e3", "font_style": null, "font_weight": 700},
                   "comment": {"color": "#7f9f7fbb", "font_style": "italic", "font_weight": null}}}}]}
      """
    let url = FileManager.default.temporaryDirectory.appending(path: "lanes-theme-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    let themes = try ZedThemeFile.load(url)
    let theme = try #require(themes.first)
    #expect(theme.name == "Dark One")
    #expect(theme.isDark)
    #expect(theme.editorBackground == 0x1E1E1E)
    #expect(theme.addedBackground == 0x294436)
    #expect(theme.removedBackground == 0x484A4A)
    #expect(theme.style(for: "keyword.return")?.color == 0x82C1BF)
    #expect(theme.style(for: "emphasis.strong")?.bold == true)
    #expect(theme.style(for: "comment")?.italic == true)
    #expect(theme.style(for: "comment")?.color == 0x7F9F7F)
  }
}

@Suite struct LanguageDetectionTests {
  @Test func detectsByExtensionAndName() {
    #expect(LanguageID.detect(path: "carrot/src/Foo.scala") == .scala)
    #expect(LanguageID.detect(path: "build.sbt") == .scala)
    #expect(LanguageID.detect(path: "icons/alertCircle.svg") == .xml)
    #expect(LanguageID.detect(path: "cypress/e2e/orders.spec.js") == .javascript)
    #expect(LanguageID.detect(path: "scripts/deploy.mts") == .typescript)
    #expect(LanguageID.detect(path: ".zshrc") == .bash)
    #expect(LanguageID.detect(path: "README") == nil)
  }
}

@Suite struct HighlighterTests {
  @Test func highlightsScalaKeywordsStringsAndComments() throws {
    let grammar = try #require(LanguageRegistry.grammar(for: .scala))
    let source = """
      // comment
      object Foo:
        val x: Int = 42
        def bar(s: String) = s"hi \\(s)"
      """
    let highlighted = Highlighter.highlight(source, grammar: grammar)
    #expect(highlighted.lines.count == 4)
    #expect(highlighted.lines[0] == [StyledRun(range: 0..<10, scope: "comment")])
    let scopes = Set(highlighted.lines.flatMap { $0.map(\.scope) })
    #expect(scopes.contains { $0.hasPrefix("keyword") })
    #expect(scopes.contains("number"))
    #expect(scopes.contains { $0.hasPrefix("type") })
  }

  @Test func everyBundledGrammarLoads() {
    let missing = LanguageID.allCases.filter { LanguageRegistry.grammar(for: $0) == nil }
    #expect(missing.isEmpty, "grammars without a working highlights query: \(missing)")
  }

  @Test func laterPatternsOverrideEarlierOnesForTheSameNode() throws {
    let grammar = try #require(LanguageRegistry.grammar(for: .javascript))
    let highlighted = Highlighter.highlight("foo(bar);\n", grammar: grammar)
    let first = highlighted.lines[0].first { $0.range.lowerBound == 0 }
    #expect(first?.scope.hasPrefix("function") == true)
  }
}
