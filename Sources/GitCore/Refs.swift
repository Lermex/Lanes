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
  /// Committer date of the commit the ref points at.
  public let committerDate: Date?

  public var id: String { fullName }

  public var remote: String? {
    guard kind == .remoteBranch else { return nil }
    return shortName.split(separator: "/", maxSplits: 1).first.map(String.init)
  }

  /// The short name without the remote prefix, so `origin/feature` and `feature` compare alike.
  public var branchName: String {
    guard let remote, shortName.hasPrefix(remote + "/") else { return shortName }
    return String(shortName.dropFirst(remote.count + 1))
  }

  public init(
    fullName: String, shortName: String, kind: RefKind, target: String, isHead: Bool, upstream: String?,
    committerDate: Date? = nil
  ) {
    self.fullName = fullName
    self.shortName = shortName
    self.kind = kind
    self.target = target
    self.isHead = isHead
    self.upstream = upstream
    self.committerDate = committerDate
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
  public static let format =
    "%(refname)%00%(objectname)%00%(*objectname)%00%(HEAD)%00%(upstream:short)%00%(committerdate:unix)%00%(*committerdate:unix)"

  public static func parse(_ output: String) -> [Ref] {
    output.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 7 else { return nil }
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
      let dateField = peeled.isEmpty ? fields[5] : fields[6]
      return Ref(
        fullName: fullName,
        shortName: shortName,
        kind: kind,
        target: peeled.isEmpty ? fields[1] : peeled,
        isHead: fields[3] == "*",
        upstream: fields[4].isEmpty ? nil : fields[4],
        committerDate: TimeInterval(dateField).map { Date(timeIntervalSince1970: $0) }
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
