import Foundation

public enum RefKind: String, Sendable, Codable, Hashable {
  case localBranch
  case remoteBranch
  case tag
}

public struct Ref: Sendable, Hashable, Identifiable {
  public let fullName: String
  public let shortName: String
  public let kind: RefKind
  public let target: String
  public let isHead: Bool
  public let upstream: String?

  public var id: String { fullName }

  public var remote: String? {
    guard kind == .remoteBranch else { return nil }
    return shortName.split(separator: "/", maxSplits: 1).first.map(String.init)
  }

  public init(fullName: String, shortName: String, kind: RefKind, target: String, isHead: Bool, upstream: String?) {
    self.fullName = fullName
    self.shortName = shortName
    self.kind = kind
    self.target = target
    self.isHead = isHead
    self.upstream = upstream
  }
}

public struct HeadState: Sendable, Equatable {
  public let sha: String?
  public let branch: String?

  public var isDetached: Bool { branch == nil }
  public var isUnborn: Bool { sha == nil }

  public init(sha: String?, branch: String?) {
    self.sha = sha
    self.branch = branch
  }
}

public enum RefParser {
  public static let format = "%(refname)%00%(objectname)%00%(*objectname)%00%(HEAD)%00%(upstream:short)"

  public static func parse(_ output: String) -> [Ref] {
    output.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 5 else { return nil }
      let fullName = fields[0]
      let kind: RefKind
      let shortName: String
      if fullName.hasPrefix("refs/heads/") {
        kind = .localBranch
        shortName = String(fullName.dropFirst("refs/heads/".count))
      } else if fullName.hasPrefix("refs/remotes/") {
        kind = .remoteBranch
        shortName = String(fullName.dropFirst("refs/remotes/".count))
      } else if fullName.hasPrefix("refs/tags/") {
        kind = .tag
        shortName = String(fullName.dropFirst("refs/tags/".count))
      } else {
        return nil
      }
      if kind == .remoteBranch && shortName.hasSuffix("/HEAD") { return nil }
      let peeled = fields[2]
      return Ref(
        fullName: fullName,
        shortName: shortName,
        kind: kind,
        target: peeled.isEmpty ? fields[1] : peeled,
        isHead: fields[3] == "*",
        upstream: fields[4].isEmpty ? nil : fields[4]
      )
    }
  }
}

extension Git {
  public func refs() async throws -> [Ref] {
    let output = try await text(["for-each-ref", "--format=\(RefParser.format)", "refs/heads", "refs/remotes", "refs/tags"])
    return RefParser.parse(output)
  }

  public func head() async throws -> HeadState {
    let branchOutput = try await run(["symbolic-ref", "--quiet", "--short", "HEAD"], allowedExitCodes: [0, 1])
    let branch = branchOutput.exitCode == 0 ? branchOutput.text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    let shaOutput = try await run(["rev-parse", "--verify", "--quiet", "HEAD"], allowedExitCodes: [0, 1])
    let sha = shaOutput.exitCode == 0 ? shaOutput.text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    return HeadState(sha: sha, branch: branch)
  }
}
