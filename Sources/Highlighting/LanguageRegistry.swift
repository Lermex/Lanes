import Foundation
import Synchronization
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHCL
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterKotlin
import TreeSitterMarkdown
import TreeSitterPython
import TreeSitterRust
import TreeSitterScala
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterXML
import TreeSitterYAML

public enum LanguageID: String, Sendable, Hashable, CaseIterable {
  case scala, swift, javascript, typescript, tsx, json, bash, python, css, html, yaml, toml, markdown, java, rust, go,
    xml, kotlin, hcl

  var targetName: String {
    switch self {
    case .scala: "TreeSitterScala"
    case .swift: "TreeSitterSwift"
    case .javascript: "TreeSitterJavaScript"
    case .typescript: "TreeSitterTypeScript"
    case .tsx: "TreeSitterTSX"
    case .json: "TreeSitterJSON"
    case .bash: "TreeSitterBash"
    case .python: "TreeSitterPython"
    case .css: "TreeSitterCSS"
    case .html: "TreeSitterHTML"
    case .yaml: "TreeSitterYAML"
    case .toml: "TreeSitterTOML"
    case .markdown: "TreeSitterMarkdown"
    case .java: "TreeSitterJava"
    case .rust: "TreeSitterRust"
    case .go: "TreeSitterGo"
    case .xml: "TreeSitterXML"
    case .kotlin: "TreeSitterKotlin"
    case .hcl: "TreeSitterHCL"
    }
  }

  var tsLanguage: OpaquePointer {
    switch self {
    case .scala: tree_sitter_scala()
    case .swift: tree_sitter_swift()
    case .javascript: tree_sitter_javascript()
    case .typescript: tree_sitter_typescript()
    case .tsx: tree_sitter_tsx()
    case .json: tree_sitter_json()
    case .bash: tree_sitter_bash()
    case .python: tree_sitter_python()
    case .css: tree_sitter_css()
    case .html: tree_sitter_html()
    case .yaml: tree_sitter_yaml()
    case .toml: tree_sitter_toml()
    case .markdown: tree_sitter_markdown()
    case .java: tree_sitter_java()
    case .rust: tree_sitter_rust()
    case .go: tree_sitter_go()
    case .xml: tree_sitter_xml()
    case .kotlin: tree_sitter_kotlin()
    case .hcl: tree_sitter_hcl()
    }
  }

  public static func detect(path: String) -> LanguageID? {
    let fileName = (path as NSString).lastPathComponent
    if let byName = byFileName[fileName] { return byName }
    let ext = (fileName as NSString).pathExtension.lowercased()
    return byExtension[ext]
  }

  private static let byFileName: [String: LanguageID] = [
    ".zshrc": .bash, ".bashrc": .bash, ".bash_profile": .bash, ".zprofile": .bash, "Jenkinsfile": .java,
  ]

  private static let byExtension: [String: LanguageID] = [
    "scala": .scala, "sc": .scala, "sbt": .scala,
    "swift": .swift,
    "js": .javascript, "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
    "ts": .typescript, "mts": .typescript, "cts": .typescript,
    "tsx": .tsx,
    "json": .json, "jsonc": .json, "avsc": .json, "webmanifest": .json,
    "sh": .bash, "bash": .bash, "zsh": .bash,
    "py": .python,
    "css": .css,
    "html": .html, "htm": .html,
    "yml": .yaml, "yaml": .yaml,
    "toml": .toml,
    "md": .markdown, "markdown": .markdown,
    "java": .java,
    "rs": .rust,
    "go": .go,
    "xml": .xml, "svg": .xml, "plist": .xml, "xib": .xml, "storyboard": .xml, "xsd": .xml, "xsl": .xml,
    "kt": .kotlin, "kts": .kotlin,
    "tf": .hcl, "hcl": .hcl, "nomad": .hcl,
  ]
}

public struct Grammar: Sendable {
  public let id: LanguageID
  public let language: Language
  public let highlights: Query
}

public enum LanguageRegistry {
  private static let cache = Mutex<[LanguageID: Grammar?]>([:])

  public static func grammar(for id: LanguageID) -> Grammar? {
    cache.withLock { cache in
      if let cached = cache[id] { return cached }
      let loaded = load(id)
      cache[id] = .some(loaded)
      return loaded
    }
  }

  public static func grammar(forPath path: String) -> Grammar? {
    LanguageID.detect(path: path).flatMap(grammar(for:))
  }

  private static func load(_ id: LanguageID) -> Grammar? {
    let language = Language(id.tsLanguage)
    guard let queryURL = bundledQueryURL(languageID: id) ?? highlightsQueryURL(targetName: id.targetName) else {
      NSLog("Lanes: no highlights.scm found for \(id.rawValue)")
      return nil
    }
    do {
      let sources = try ([queryURL] + inheritedQueryURLs(for: id)).map { try Data(contentsOf: $0) }
      let query = try Query(language: language, data: Data(sources.joined(separator: Data("\n".utf8))))
      return Grammar(id: id, language: language, highlights: query)
    } catch {
      NSLog("Lanes: highlights query for \(id.rawValue) failed to compile: \(error)")
      return nil
    }
  }

  // tree-sitter-typescript's own highlights only cover the TypeScript additions; the grammar's
  // tree-sitter.json appends JavaScript's queries (and the JSX ones for TSX), so we do the same.
  private static func inheritedQueryURLs(for id: LanguageID) -> [URL] {
    guard id == .typescript || id == .tsx, let javascript = highlightsQueryURL(targetName: LanguageID.javascript.targetName) else {
      return []
    }
    let jsx = javascript.deletingLastPathComponent().appending(path: "highlights-jsx.scm")
    return (id == .tsx && FileManager.default.isReadableFile(atPath: jsx.path) ? [jsx] : []) + [javascript]
  }

  private final class BundleMarker {}

  private static var resourceRoots: [URL] {
    let hostBundle = Bundle(for: BundleMarker.self)
    return [
      Bundle.main.resourceURL,
      Bundle.main.executableURL?.deletingLastPathComponent(),
      hostBundle.resourceURL,
      hostBundle.bundleURL.deletingLastPathComponent(),
    ].compactMap { $0 }
  }

  private static func bundles(withSuffix suffix: String) -> [URL] {
    resourceRoots.flatMap { root -> [URL] in
      let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
      return entries.filter { $0.pathExtension == "bundle" && $0.deletingPathExtension().lastPathComponent.hasSuffix(suffix) }
    }
  }

  private static func bundledQueryURL(languageID: LanguageID) -> URL? {
    bundles(withSuffix: "_Highlighting").lazy.compactMap { bundle -> URL? in
      let candidates = [
        bundle.appending(path: "Queries/\(languageID.rawValue)/highlights.scm"),
        bundle.appending(path: "Contents/Resources/Queries/\(languageID.rawValue)/highlights.scm"),
      ]
      return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }.first
  }

  private static func highlightsQueryURL(targetName: String) -> URL? {
    bundles(withSuffix: "_\(targetName)").lazy.compactMap(firstHighlightsFile).first
  }

  private static func firstHighlightsFile(in bundle: URL) -> URL? {
    guard let enumerator = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil) else { return nil }
    for case let url as URL in enumerator where url.lastPathComponent == "highlights.scm" {
      return url
    }
    return nil
  }
}
