import Foundation

public struct Stash: Sendable, Hashable, Identifiable {
  public let index: Int
  public let commit: Commit

  public var id: String { commit.sha }
  public var reference: String { "stash@{\(index)}" }

  /// git names stashes "WIP on <branch>: <sha> <subject>" or "On <branch>: <message>"
  public var branch: String? { split?.branch }
  public var title: String { split?.title ?? commit.subject }

  private var split: (branch: String, title: String)? {
    let subject = commit.subject
    for prefix in ["WIP on ", "On "] where subject.hasPrefix(prefix) {
      let rest = subject.dropFirst(prefix.count)
      guard let colon = rest.firstIndex(of: ":") else { continue }
      let title = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      return (String(rest[..<colon]), title)
    }
    return nil
  }

  public init(index: Int, commit: Commit) {
    self.index = index
    self.commit = commit
  }
}

extension Git {
  public func stashes() async throws -> [Stash] {
    let output = try await text(["stash", "list", "--format=\(LogParser.format)"])
    return LogParser.parse(output).enumerated().map { Stash(index: $0, commit: $1) }
  }

  public func stashChanges(message: String?) async throws {
    try await run(["stash", "push", "--include-untracked", "--quiet"] + (message.map { ["--message", $0] } ?? []))
  }

  public func applyStash(_ index: Int) async throws {
    try await run(["stash", "apply", "--quiet", "stash@{\(index)}"])
  }

  public func popStash(_ index: Int) async throws {
    try await run(["stash", "pop", "--quiet", "stash@{\(index)}"])
  }

  public func dropStash(_ index: Int) async throws {
    try await run(["stash", "drop", "--quiet", "stash@{\(index)}"])
  }
}
