/// Maps the capture names used by the bundled grammars (nvim-treesitter style) onto Zed's theme scopes.
public enum ScopeNormalizer {
  public static func normalize(_ captureName: String) -> String? {
    let components = captureName.split(separator: ".").map(String.init)
    guard let head = components.first, !head.hasPrefix("_") else { return nil }
    let rest = components.dropFirst().joined(separator: ".")
    func withRest(_ base: String) -> String { rest.isEmpty ? base : base + "." + rest }
    switch head {
    case "spell", "nospell", "none", "error", "embedded": return nil
    case "keyword": return withRest("keyword")
    case "conditional", "repeat", "include", "import", "exception", "storageclass": return "keyword.\(head)"
    case "supports", "media", "charset", "keyframes": return "keyword"
    case "function":
      if components.contains("builtin") || components.contains("macro") { return "function.special" }
      return withRest("function")
    case "method": return "function.method"
    case "constructor": return "constructor"
    case "type":
      if components.contains("qualifier") { return "keyword" }
      if components.contains("definition") { return "type" }
      return withRest("type")
    case "number", "float": return "number"
    case "boolean": return "boolean"
    case "constant": return "constant"
    case "variable":
      if components.contains("builtin") { return "variable.special" }
      if components.contains("parameter") { return "variable.parameter" }
      if components.contains("member") { return "property" }
      return "variable"
    case "parameter": return "variable.parameter"
    case "field", "property": return "property"
    case "attribute": return "attribute"
    case "tag":
      if components.contains("error") { return nil }
      return components.contains("attribute") ? "attribute" : "tag"
    case "operator": return "operator"
    case "punctuation": return withRest("punctuation")
    case "string":
      if components.contains("regex") || components.contains("regexp") { return "string.regex" }
      if components.contains("escape") { return "string.escape" }
      return withRest("string")
    case "character": return components.contains("special") ? "string.escape" : "string"
    case "escape": return "string.escape"
    case "comment": return components.contains("documentation") ? "comment.doc" : "comment"
    case "namespace", "module": return "namespace"
    case "label": return "label"
    case "markup", "text":
      if components.contains("heading") || components.contains("title") { return "title" }
      if components.contains("raw") || components.contains("literal") { return "text.literal" }
      if components.contains("link") || components.contains("uri") { return "link_uri" }
      if components.contains("italic") || components.contains("emphasis") { return "emphasis" }
      if components.contains("bold") || components.contains("strong") { return "emphasis.strong" }
      return nil
    default: return head
    }
  }
}
