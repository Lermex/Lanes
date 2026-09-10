// swift-tools-version: 6.2
import PackageDescription

let grammars: [(name: String, url: String, version: Version, products: [String])] = [
  ("tree-sitter-scala", "https://github.com/tree-sitter/tree-sitter-scala", "0.26.2", ["TreeSitterScala"]),
  ("tree-sitter-typescript", "https://github.com/tree-sitter/tree-sitter-typescript", "0.23.2", ["TreeSitterTypeScript"]),
  ("tree-sitter-json", "https://github.com/tree-sitter/tree-sitter-json", "0.24.8", ["TreeSitterJSON"]),
  ("tree-sitter-bash", "https://github.com/tree-sitter/tree-sitter-bash", "0.25.1", ["TreeSitterBash"]),
  ("tree-sitter-html", "https://github.com/tree-sitter/tree-sitter-html", "0.23.2", ["TreeSitterHTML"]),
  ("tree-sitter-toml", "https://github.com/tree-sitter-grammars/tree-sitter-toml", "0.7.0", ["TreeSitterTOML"]),
  ("tree-sitter-markdown", "https://github.com/tree-sitter-grammars/tree-sitter-markdown", "0.5.3", ["TreeSitterMarkdown"]),
  ("tree-sitter-java", "https://github.com/tree-sitter/tree-sitter-java", "0.23.5", ["TreeSitterJava"]),
  ("tree-sitter-rust", "https://github.com/tree-sitter/tree-sitter-rust", "0.24.2", ["TreeSitterRust"]),
  ("tree-sitter-go", "https://github.com/tree-sitter/tree-sitter-go", "0.25.0", ["TreeSitterGo"]),
  ("tree-sitter-xml", "https://github.com/tree-sitter-grammars/tree-sitter-xml", "0.7.0", ["TreeSitterXML"]),
  ("tree-sitter-kotlin", "https://github.com/fwcd/tree-sitter-kotlin", "0.3.8", ["TreeSitterKotlin"]),
  ("tree-sitter-hcl", "https://github.com/tree-sitter-grammars/tree-sitter-hcl", "1.2.0", ["TreeSitterHCL"]),
]

// Their manifests probe src/scanner.c with a relative path that SwiftPM 6 evaluates elsewhere, so the
// scanner never compiles; Sources/GrammarScanners carries copies matching these exact versions.
let scannerlessGrammars: [(name: String, url: String, version: Version, products: [String])] = [
  ("tree-sitter-javascript", "https://github.com/tree-sitter/tree-sitter-javascript", "0.25.0", ["TreeSitterJavaScript"]),
  ("tree-sitter-python", "https://github.com/tree-sitter/tree-sitter-python", "0.25.0", ["TreeSitterPython"]),
  ("tree-sitter-css", "https://github.com/tree-sitter/tree-sitter-css", "0.25.0", ["TreeSitterCSS"]),
  ("tree-sitter-yaml", "https://github.com/tree-sitter-grammars/tree-sitter-yaml", "0.7.2", ["TreeSitterYAML"]),
]

let package = Package(
  name: "Lanes",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.25.0"),
    // tags carry no generated parser; this branch does
    .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", branch: "with-generated-files"),
  ] + grammars.map { .package(url: $0.url, from: $0.version) }
    + scannerlessGrammars.map { .package(url: $0.url, exact: $0.version) },
  targets: [
    .target(name: "GitCore"),
    .target(
      name: "GrammarScanners",
      sources: ["javascript/scanner.c", "python/scanner.c", "yaml/scanner.c", "css/scanner.c"]
    ),
    .target(
      name: "Highlighting",
      dependencies: [
        .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
        .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
        "GrammarScanners",
      ] + (grammars + scannerlessGrammars).flatMap { g in g.products.map { .product(name: $0, package: g.name) } },
      resources: [.copy("Queries")]
    ),
    .executableTarget(
      name: "Lanes",
      dependencies: ["GitCore", "Highlighting", .product(name: "Sparkle", package: "Sparkle")],
      swiftSettings: [.unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=300"])]
    ),
    .testTarget(name: "GitCoreTests", dependencies: ["GitCore"]),
    .testTarget(name: "HighlightingTests", dependencies: ["Highlighting"]),
    .testTarget(name: "LanesTests", dependencies: ["Lanes"]),
  ]
)
