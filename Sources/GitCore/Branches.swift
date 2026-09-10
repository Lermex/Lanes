import Foundation

extension Git {
  public func switchBranch(_ name: String) async throws {
    try await run(["switch", "--quiet", name])
  }

  /// Creates a local branch tracking `remoteBranch` (e.g. `origin/feature`) and switches to it.
  public func switchToTrackingBranch(_ remoteBranch: String) async throws {
    try await run(["switch", "--quiet", "--track", remoteBranch])
  }

  public func push(branch: String, to remote: String, setUpstream: Bool) async throws {
    try await run(["push", "--quiet"] + (setUpstream ? ["--set-upstream"] : []) + [remote, branch])
  }

  public func renameBranch(_ name: String, to newName: String) async throws {
    try await run(["branch", "--move", name, newName])
  }

  /// Throws a `GitError` mentioning "not fully merged" when git refuses a non-forced delete.
  public func deleteBranch(_ name: String, force: Bool) async throws {
    try await run(["branch", force ? "-D" : "-d", name])
  }

  public func deleteRemoteBranch(_ name: String, on remote: String) async throws {
    try await run(["push", "--quiet", remote, "--delete", name])
  }

  public func deleteTag(_ name: String) async throws {
    try await run(["tag", "--delete", name])
  }
}

extension GitError {
  public var isNotFullyMerged: Bool { stderr.contains("not fully merged") }
}
