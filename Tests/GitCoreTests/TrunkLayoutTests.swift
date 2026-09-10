import Foundation
import Testing
@testable import GitCore

@Suite struct TrunkLayoutTests {
  func commit(_ sha: String, _ parents: [String], date: Int, subject: String = "") -> Commit {
    Commit(
      sha: sha, parents: parents, authorName: "a", authorEmail: "a@x", authorDate: Date(timeIntervalSince1970: TimeInterval(date)),
      committerDate: Date(timeIntervalSince1970: TimeInterval(date)), decorations: [], subject: subject.isEmpty ? sha : subject, body: ""
    )
  }

  // trunk: t3 -> t2 -> merge(m, side s2 -> s1 -> t1) -> t1 -> t0 ; open branch f2 -> f1 forked from t2 ; stacked g1 on f2
  var commits: [Commit] {
    [
      commit("g1", ["f2"], date: 100),
      commit("f2", ["f1"], date: 90),
      commit("t3", ["t2"], date: 80),
      commit("f1", ["t2"], date: 70),
      commit("t2", ["m"], date: 60),
      commit("m", ["t1", "s2"], date: 50, subject: "Merge branch 'side'"),
      commit("s2", ["s1"], date: 45),
      commit("s1", ["t1"], date: 40),
      commit("t1", ["t0"], date: 30),
      commit("t0", [], date: 20),
    ]
  }

  var tips: [TrunkTip] {
    [
      TrunkTip(fullName: "refs/heads/feature", shortName: "feature", sha: "f2", isHead: false, priority: 0),
      TrunkTip(fullName: "refs/remotes/origin/feature", shortName: "origin/feature", sha: "f2", isHead: false, priority: 1),
      TrunkTip(fullName: "refs/heads/stacked", shortName: "stacked", sha: "g1", isHead: true, priority: 0),
    ]
  }

  @Test func groupsBranchesAndPlacesCapsulesAboveForkCommits() throws {
    let layout = try #require(TrunkLayout.compute(commits: commits, trunkSha: "t3", tips: tips, expanded: []))
    let feature = try #require(layout.group(id: "refs/heads/feature"))
    #expect(feature.names == ["feature", "origin/feature"])
    #expect(feature.commits.map(\.sha) == ["f2", "f1"])
    #expect(feature.forkSha == "t2")
    #expect(feature.behind == 1)
    let stacked = try #require(layout.group(id: "refs/heads/stacked"))
    #expect(stacked.commits.map(\.sha) == ["g1"])
    #expect(stacked.forkSha == "t2")
    #expect(stacked.isHead)
    let merged = try #require(layout.group(id: "merge:m"))
    #expect(merged.names == ["side"])
    #expect(merged.commits.map(\.sha) == ["s2", "s1"])
    #expect(merged.forkSha == "t1")

    let kinds = layout.rows.map(\.kind)
    let shas: [String] = kinds.map {
      switch $0 {
      case .trunk(let c): "T:\(c.sha)"
      case .capsule(let g): "C:\(g.id)"
      case .branchCommit(let c, _): "B:\(c.sha)"
      }
    }
    #expect(shas == ["T:t3", "C:refs/heads/stacked", "C:refs/heads/feature", "T:t2", "T:m", "C:merge:m", "T:t1", "T:t0"])
  }

  @Test func lanesStayLocalAndBendIntoTheForkCommit() throws {
    let layout = try #require(TrunkLayout.compute(commits: commits, trunkSha: "t3", tips: tips, expanded: ["refs/heads/feature"]))
    let rowKinds = layout.rows.map(\.kind)
    #expect(rowKinds.count == 9)
    // an expanded group is its commits with the tip on top; the capsule row only stands in while collapsed
    let featureRows = rowKinds.compactMap { if case .branchCommit(let c, "refs/heads/feature") = $0 { return c.sha } else { return nil } }
    #expect(featureRows == ["f2", "f1"])
    #expect(!rowKinds.contains { if case .capsule(let g) = $0 { return g.id == "refs/heads/feature" } else { return false } })
    // capsule blocks stacked above the fork commit t2 share lane 1; each joins the trunk at the end of its block
    let capsuleLanes = layout.rows.filter { if case .capsule(let g) = $0.kind { return g.forkSha == "t2" } else { return false } }.map(\.graph.nodeLane)
    #expect(Set(capsuleLanes) == [1])
    let stackedIndex = try #require(rowKinds.firstIndex { if case .capsule(let g) = $0 { return g.id == "refs/heads/stacked" } else { return false } })
    #expect(layout.rows[stackedIndex].graph.outgoing.contains { $0.fromLane == 1 && $0.toLane == 0 && $0.startsAtNode })
    let t2Index = try #require(rowKinds.firstIndex { if case .trunk(let c) = $0 { return c.sha == "t2" } else { return false } })
    let entering = layout.rows[t2Index].graph.incoming.filter { $0.toLane == 0 && $0.fromLane != 0 }
    #expect(entering.count == 1)
    #expect(layout.maxLaneCount == 2)
    // the merged branch starts its lane at the merge commit and reaches its capsule below
    let mergeIndex = try #require(rowKinds.firstIndex { if case .trunk(let c) = $0 { return c.sha == "m" } else { return false } })
    #expect(layout.rows[mergeIndex].graph.outgoing.contains { $0.fromLane == 0 && $0.toLane == 1 && $0.startsAtNode })
    // trunk line runs through every row down to the last trunk commit
    #expect(layout.rows.dropLast().allSatisfy { $0.graph.outgoing.contains { $0.fromLane == 0 && $0.toLane == 0 } })
  }

  @Test func returnsNilWhenTheTrunkIsNotLoaded() {
    #expect(TrunkLayout.compute(commits: commits, trunkSha: "nope", tips: tips, expanded: []) == nil)
  }
}
