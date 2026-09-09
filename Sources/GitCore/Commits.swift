import Foundation

public enum ResetMode: String, Sendable, CaseIterable {
  case soft
  case mixed
  case hard
}

extension Git {
  public func checkoutDetached(_ revision: String) async throws {
    try await run(["switch", "--quiet", "--detach", revision])
  }

  public func createBranch(_ name: String, at revision: String, switchTo: Bool) async throws {
    if switchTo {
      try await run(["switch", "--quiet", "--create", name, revision])
    } else {
      try await run(["branch", name, revision])
    }
  }

  public func createTag(_ name: String, at revision: String) async throws {
    try await run(["tag", name, revision])
  }

  public func cherryPick(_ sha: String) async throws {
    try await run(["cherry-pick", sha])
  }

  public func revert(_ sha: String) async throws {
    try await run(["revert", "--no-edit", sha])
  }

  public func reset(to revision: String, mode: ResetMode) async throws {
    try await run(["reset", "--\(mode.rawValue)", "--quiet", revision])
  }

  public func remoteURL(_ remote: String) async throws -> String? {
    let output = try await run(["remote", "get-url", remote], allowedExitCodes: [0, 2, 128])
    guard output.exitCode == 0 else { return nil }
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum RemoteWebURL {
  /// The browsable URL behind a fetch URL, for GitHub-style hosts: `git@github.com:o/r.git` and
  /// `https://github.com/o/r.git` both become `https://github.com/o/r`.
  public static func webURL(for remote: String) -> URL? {
    var text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("ssh://") {
      text = String(text.dropFirst("ssh://".count))
      if let at = text.firstIndex(of: "@") { text = String(text[text.index(after: at)...]) }
      text = "https://" + text
    } else if let colon = text.firstIndex(of: ":"), text.hasPrefix("git@") {
      let host = text[text.index(text.startIndex, offsetBy: 4)..<colon]
      text = "https://\(host)/\(text[text.index(after: colon)...])"
    }
    guard text.hasPrefix("http://") || text.hasPrefix("https://") else { return nil }
    if text.hasSuffix(".git") { text.removeLast(4) }
    return URL(string: text)
  }
}
