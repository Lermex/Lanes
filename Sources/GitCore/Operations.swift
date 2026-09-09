import Foundation

extension Git {
  public func stage(paths: [String]) async throws {
    try await run(["add", "--"] + paths)
  }

  public func unstage(paths: [String]) async throws {
    try await run(["restore", "--staged", "--"] + paths)
  }

  public func stageHunk(_ hunk: Hunk, of file: FileDiff) async throws {
    try await applyToIndex(file.patch(for: hunk), reverse: false)
  }

  public func unstageHunk(_ hunk: Hunk, of file: FileDiff) async throws {
    try await applyToIndex(file.patch(for: hunk), reverse: true)
  }

  public func stageLines(_ lines: Set<Int>, of hunk: Hunk, in file: FileDiff) async throws {
    guard let partial = hunk.selecting(lines: lines) else { return }
    try await applyToIndex(file.partialPatch(partial, reverse: false), reverse: false)
  }

  public func unstageLines(_ lines: Set<Int>, of hunk: Hunk, in file: FileDiff) async throws {
    guard let partial = hunk.reversed().selecting(lines: lines) else { return }
    try await applyToIndex(file.partialPatch(partial, reverse: true), reverse: false)
  }

  private func applyToIndex(_ patch: String, reverse: Bool) async throws {
    let arguments = ["apply", "--cached", "--whitespace=nowarn", "--recount"] + (reverse ? ["--reverse"] : [])
    try await run(arguments + ["-"], stdin: Data(patch.utf8))
  }

  public func commit(message: String, amend: Bool) async throws {
    let arguments = ["commit", "--quiet", "--file=-"] + (amend ? ["--amend"] : [])
    try await run(arguments, stdin: Data(message.utf8))
  }

  public func fetchAll() async throws {
    try await run(["fetch", "--all", "--prune", "--quiet"])
  }

  public func lastCommitMessage() async throws -> String {
    try await text(["log", "-1", "--format=%B"]).trimmingCharacters(in: .newlines)
  }
}
