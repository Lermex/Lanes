import Foundation

public struct TrunkTip: Sendable, Hashable {
  public let fullName: String
  public let shortName: String
  public let sha: String
  public let isHead: Bool
  public let priority: Int

  public init(fullName: String, shortName: String, sha: String, isHead: Bool, priority: Int) {
    self.fullName = fullName
    self.shortName = shortName
    self.sha = sha
    self.isHead = isHead
    self.priority = priority
  }
}

public struct BranchGroup: Sendable, Hashable, Identifiable {
  public let id: String
  public let names: [String]
  public let tipSha: String
  public let commits: [Commit]
  public let forkSha: String?
  public let behind: Int?
  public let mergedAt: String?
  public let isHead: Bool
  public let colorIndex: Int

  public var tip: Commit? { commits.first { $0.sha == tipSha } ?? commits.first }
  public var isMerged: Bool { mergedAt != nil }
}

public enum TrunkRowKind: Sendable, Hashable {
  case trunk(Commit)
  case capsule(BranchGroup)
  case branchCommit(Commit, groupID: String)
}

public struct TrunkRow: Sendable, Hashable {
  public let kind: TrunkRowKind
  public let graph: GraphRow
}

public struct TrunkLayout: Sendable, Hashable {
  public let rows: [TrunkRow]
  public let groups: [BranchGroup]
  public let maxLaneCount: Int

  public func group(id: String) -> BranchGroup? { groups.first { $0.id == id } }

  public static func compute(commits: [Commit], trunkSha: String, tips: [TrunkTip], expanded: Set<String>) -> TrunkLayout? {
    var builder = Builder(commits: commits, trunkSha: trunkSha)
    guard builder.trunkOrder.count > 0 else { return nil }
    builder.claimMergedBranches()
    builder.claimTipBranches(tips)
    builder.claimOrphans()
    return builder.layout(expanded: expanded)
  }

  private struct Builder {
    let commits: [Commit]
    let bySha: [String: Commit]
    let logIndex: [String: Int]
    var trunkOrder: [String] = []
    var trunkIndex: [String: Int] = [:]
    var owner: [String: String] = [:]
    var groupOrder: [String] = []
    var groupMembers: [String: [String]] = [:]
    var groupNames: [String: [String]] = [:]
    var groupTip: [String: String] = [:]
    var groupMergedAt: [String: String] = [:]
    var groupIsHead: [String: Bool] = [:]

    init(commits: [Commit], trunkSha: String) {
      self.commits = commits
      bySha = Dictionary(commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
      logIndex = Dictionary(commits.enumerated().map { ($1.sha, $0) }, uniquingKeysWith: { first, _ in first })
      var sha: String? = trunkSha
      while let current = sha, let commit = bySha[current], trunkIndex[current] == nil {
        trunkIndex[current] = trunkOrder.count
        trunkOrder.append(current)
        sha = commit.parents.first
      }
    }

    func isTrunk(_ sha: String) -> Bool { trunkIndex[sha] != nil }

    mutating func claim(from start: String, group: String, firstParentOnly: Bool) {
      var queue = [start]
      while let sha = queue.popLast() {
        guard let commit = bySha[sha], !isTrunk(sha), owner[sha] == nil else { continue }
        owner[sha] = group
        groupMembers[group, default: []].append(sha)
        queue.append(contentsOf: firstParentOnly ? Array(commit.parents.prefix(1)) : commit.parents.reversed())
      }
    }

    mutating func register(group: String, names: [String], tip: String, mergedAt: String?, isHead: Bool) {
      groupOrder.append(group)
      groupNames[group] = names
      groupTip[group] = tip
      groupMergedAt[group] = mergedAt
      groupIsHead[group] = isHead
    }

    mutating func claimMergedBranches() {
      for sha in trunkOrder {
        guard let merge = bySha[sha], merge.parents.count > 1 else { continue }
        let sideParents = merge.parents.dropFirst().filter { bySha[$0] != nil && !isTrunk($0) && owner[$0] == nil }
        guard let first = sideParents.first else { continue }
        let group = "merge:\(sha)"
        register(group: group, names: [Self.mergedBranchName(merge)], tip: first, mergedAt: sha, isHead: false)
        for parent in sideParents { claim(from: parent, group: group, firstParentOnly: false) }
        if groupMembers[group, default: []].isEmpty { unregister(group) }
      }
    }

    mutating func claimTipBranches(_ tips: [TrunkTip]) {
      let usable = tips.filter { bySha[$0.sha] != nil && !isTrunk($0.sha) }
      let byTipSha = Dictionary(grouping: usable, by: \.sha)
      let ordered = byTipSha.values
        .map { refs in refs.sorted { ($0.isHead ? 0 : 1, $0.priority, $0.shortName) < ($1.isHead ? 0 : 1, $1.priority, $1.shortName) } }
        .sorted { lhs, rhs in
          let lhsDate = bySha[lhs[0].sha]?.committerDate ?? .distantPast
          let rhsDate = bySha[rhs[0].sha]?.committerDate ?? .distantPast
          return lhsDate != rhsDate ? lhsDate < rhsDate : lhs[0].fullName < rhs[0].fullName
        }
      for refs in ordered {
        let primary = refs[0]
        let group = primary.fullName
        register(group: group, names: refs.map(\.shortName), tip: primary.sha, mergedAt: nil, isHead: refs.contains(where: \.isHead))
        claim(from: primary.sha, group: group, firstParentOnly: true)
        if groupMembers[group, default: []].isEmpty { unregister(group) }
      }
      for group in groupOrder where groupMergedAt[group] == nil {
        for sha in groupMembers[group, default: []] {
          for parent in bySha[sha]?.parents.dropFirst() ?? [] { claim(from: parent, group: group, firstParentOnly: false) }
        }
      }
    }

    mutating func claimOrphans() {
      for commit in commits where !isTrunk(commit.sha) && owner[commit.sha] == nil {
        let group = "orphan:\(commit.sha)"
        register(group: group, names: [commit.shortSha], tip: commit.sha, mergedAt: nil, isHead: false)
        claim(from: commit.sha, group: group, firstParentOnly: false)
      }
    }

    private mutating func unregister(_ group: String) {
      groupOrder.removeAll { $0 == group }
      groupNames[group] = nil
      groupTip[group] = nil
      groupMergedAt[group] = nil
      groupIsHead[group] = nil
    }

    func forkPoint(of group: String) -> String? {
      var sha: String? = groupTip[group]
      var visited: Set<String> = []
      while let current = sha, let commit = bySha[current], visited.insert(current).inserted {
        if isTrunk(current) { return current }
        sha = commit.parents.first
      }
      return nil
    }

    func layout(expanded: Set<String>) -> TrunkLayout {
      let groups = groupOrder.enumerated().map { index, id -> BranchGroup in
        let members = groupMembers[id, default: []].sorted { (logIndex[$0] ?? 0) < (logIndex[$1] ?? 0) }
        let fork = forkPoint(of: id)
        return BranchGroup(
          id: id,
          names: groupNames[id] ?? [],
          tipSha: groupTip[id] ?? "",
          commits: members.compactMap { bySha[$0] },
          forkSha: fork,
          behind: fork.flatMap { trunkIndex[$0] },
          mergedAt: groupMergedAt[id],
          isHead: groupIsHead[id] ?? false,
          colorIndex: index + 1
        )
      }
      let byFork = Dictionary(grouping: groups, by: { $0.forkSha ?? "" })
      let newestFirst: (BranchGroup, BranchGroup) -> Bool = { lhs, rhs in
        (lhs.tip?.committerDate ?? .distantPast) > (rhs.tip?.committerDate ?? .distantPast)
      }

      var kinds: [TrunkRowKind] = []
      var groupStart: [String: Int] = [:]
      var groupEnd: [String: Int] = [:]
      var trunkRowIndex: [String: Int] = [:]
      // a block is a collapsed group's capsule row, or an expanded group's commits with the tip on top; its
      // line joins the trunk right below the block, so blocks stacked above one fork commit share a lane,
      // while merged branches span from their merge commit
      func emit(_ group: BranchGroup) {
        groupStart[group.id] = kinds.count
        if expanded.contains(group.id), !group.commits.isEmpty {
          kinds.append(contentsOf: group.commits.map { .branchCommit($0, groupID: group.id) })
        } else {
          kinds.append(.capsule(group))
        }
        groupEnd[group.id] = kinds.count
      }
      for sha in trunkOrder {
        for group in (byFork[sha] ?? []).sorted(by: newestFirst) { emit(group) }
        trunkRowIndex[sha] = kinds.count
        if let commit = bySha[sha] { kinds.append(.trunk(commit)) }
      }
      for group in (byFork[""] ?? []).sorted(by: newestFirst) { emit(group) }
      for group in groups where group.isMerged {
        if let mergeRow = group.mergedAt.flatMap({ trunkRowIndex[$0] }) { groupStart[group.id] = mergeRow }
      }

      var laneOf: [String: Int] = [:]
      var occupied: [(lane: Int, start: Int, last: Int)] = []
      for group in groups.sorted(by: { (groupStart[$0.id] ?? 0, $0.colorIndex) < (groupStart[$1.id] ?? 0, $1.colorIndex) }) {
        guard let start = groupStart[group.id], let end = groupEnd[group.id], end > start else { continue }
        let last = end - 1
        var lane = 1
        while occupied.contains(where: { $0.lane == lane && $0.start <= last && start <= $0.last }) { lane += 1 }
        laneOf[group.id] = lane
        occupied.append((lane, start, last))
      }

      let lastTrunkRow = trunkOrder.compactMap { trunkRowIndex[$0] }.max() ?? -1
      var outgoing: [[GraphTransition]] = Array(repeating: [], count: kinds.count)
      for row in kinds.indices where row < lastTrunkRow {
        let isTrunkNode: Bool = if case .trunk = kinds[row] { true } else { false }
        outgoing[row].append(GraphTransition(fromLane: 0, toLane: 0, colorIndex: 0, startsAtNode: isTrunkNode))
      }
      for group in groups {
        guard let start = groupStart[group.id], let end = groupEnd[group.id], let lane = laneOf[group.id], end > start else { continue }
        let forkIsTrunk = group.forkSha != nil
        for row in start..<end {
          let entersTrunk = row == end - 1 && forkIsTrunk
          if row == end - 1, !forkIsTrunk { continue }
          let fromLane = (row == start && group.isMerged) ? 0 : lane
          outgoing[row].append(
            GraphTransition(
              fromLane: fromLane, toLane: entersTrunk ? 0 : lane, colorIndex: group.colorIndex,
              startsAtNode: row == start || entersTrunk
            )
          )
        }
      }
      var laneCounts = Array(repeating: 1, count: kinds.count)
      for (lane, start, last) in occupied {
        for row in start...last { laneCounts[row] = max(laneCounts[row], lane + 1) }
      }
      let rows = kinds.indices.map { row -> TrunkRow in
        let (nodeLane, color): (Int, Int) =
          switch kinds[row] {
          case .trunk: (0, 0)
          case .capsule(let group): (laneOf[group.id] ?? 1, group.colorIndex)
          case .branchCommit(_, let groupID): (laneOf[groupID] ?? 1, groups.first { $0.id == groupID }?.colorIndex ?? 1)
          }
        return TrunkRow(
          kind: kinds[row],
          graph: GraphRow(
            nodeLane: nodeLane,
            nodeColorIndex: color,
            incoming: row > 0 ? outgoing[row - 1] : [],
            outgoing: outgoing[row],
            laneCount: laneCounts[row]
          )
        )
      }
      return TrunkLayout(rows: rows, groups: groups, maxLaneCount: laneCounts.max() ?? 1)
    }

    static func mergedBranchName(_ merge: Commit) -> String {
      let subject = merge.subject
      if let quoted = subject.split(separator: "'").dropFirst().first { return String(quoted) }
      if subject.hasPrefix("Merge pull request "), let from = subject.range(of: " from ") {
        return String(subject[from.upperBound...]).split(separator: " ").first.map(String.init) ?? subject
      }
      if subject.hasPrefix("Merge ") {
        let rest = subject.dropFirst("Merge ".count)
        return String(rest.split(separator: " into ").first ?? rest)
      }
      return subject
    }
  }
}
