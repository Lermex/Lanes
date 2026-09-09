import Foundation

extension Git {
  /// The best common ancestor of two revisions, or nil when they share no history.
  public func mergeBase(_ a: String, _ b: String) async throws -> String? {
    let output = try await run(["merge-base", a, b], allowedExitCodes: [0, 1])
    guard output.exitCode == 0 else { return nil }
    return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Committer dates of the given commits, keyed by full sha.
  public func commitDates(_ shas: [String]) async throws -> [String: Date] {
    guard !shas.isEmpty else { return [:] }
    let output = try await text(["log", "--no-walk=unsorted", "--format=%H%x00%ct"] + shas)
    return Dictionary(uniqueKeysWithValues: output.split(separator: "\n").compactMap { line -> (String, Date)? in
      let fields = line.split(separator: "\u{0}")
      guard fields.count == 2, let seconds = TimeInterval(fields[1]) else { return nil }
      return (String(fields[0]), Date(timeIntervalSince1970: seconds))
    })
  }
}
