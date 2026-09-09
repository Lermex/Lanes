import Foundation
import GitCore
import Testing
@testable import Lanes

@Suite struct BranchFilterTests {
  func ref(_ fullName: String, isHead: Bool = false) -> Ref {
    let kind: RefKind = fullName.hasPrefix("refs/remotes/") ? .remoteBranch : fullName.hasPrefix("refs/tags/") ? .tag : .localBranch
    let short = fullName.split(separator: "/", maxSplits: 2).last.map(String.init) ?? fullName
    return Ref(fullName: fullName, shortName: short, kind: kind, target: "0", isHead: isHead, upstream: nil)
  }

  var refs: [Ref] {
    [
      ref("refs/heads/master", isHead: true), ref("refs/heads/feature"),
      ref("refs/remotes/origin/master"), ref("refs/remotes/mirror/master"), ref("refs/tags/v1"),
    ]
  }

  @Test func showAllListsEveryVisibleRemoteExplicitly() {
    var filter = BranchFilter.initial
    #expect(filter.revisions(refs: refs) == ["HEAD", "--branches", "--remotes=mirror", "--remotes=origin"])
    filter.hiddenRemotes = ["mirror"]
    #expect(filter.revisions(refs: refs) == ["HEAD", "--branches", "--remotes=origin"])
    filter.includeTags = true
    #expect(filter.revisions(refs: refs).last == "--tags")
  }

  @Test func selectedModeDropsRefsOfHiddenRemotesAndUnknownRefs() {
    var filter = BranchFilter(showAll: false, selected: ["refs/heads/feature", "refs/remotes/mirror/master", "refs/heads/gone"], includeTags: false, hiddenRemotes: ["mirror"])
    #expect(filter.revisions(refs: refs) == ["HEAD", "refs/heads/feature"])
    #expect(!filter.isShown(ref("refs/remotes/mirror/master")))
    filter.hiddenRemotes = []
    #expect(filter.isShown(ref("refs/remotes/mirror/master")))
  }

  @Test func uncheckingWhileShowingAllStartsFromEverythingChecked() {
    var filter = BranchFilter.initial
    filter.setShown(ref("refs/heads/feature"), false, allRefs: refs)
    #expect(!filter.showAll)
    #expect(filter.selected == ["refs/heads/master", "refs/remotes/origin/master", "refs/remotes/mirror/master"])
    #expect(filter.isShown(ref("refs/heads/master", isHead: true)))
  }

  @Test func decodesFiltersSavedBeforeHiddenRemotesExisted() throws {
    let legacy = Data(#"{"showAll":false,"selected":["refs/heads/x"],"includeTags":true}"#.utf8)
    let filter = try JSONDecoder().decode(BranchFilter.self, from: legacy)
    #expect(filter.hiddenRemotes.isEmpty)
    #expect(filter.selected == ["refs/heads/x"])
  }
}
