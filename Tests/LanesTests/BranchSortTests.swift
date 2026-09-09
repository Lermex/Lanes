import Foundation
import GitCore
import Testing
@testable import Lanes

@Suite struct BranchSortTests {
  static func ref(_ name: String, date: TimeInterval?) -> Ref {
    Ref(
      fullName: "refs/heads/\(name)", shortName: name, kind: .localBranch, target: name, isHead: false, upstream: nil,
      committerDate: date.map { Date(timeIntervalSince1970: $0) }
    )
  }

  func pullRequest(_ branch: String) throws -> PullRequest {
    let json = """
      {"number": 7, "title": "t", "url": "https://example.com/pull/7", "headRefName": "\(branch)", "isDraft": false, "author": null}
      """
    return try JSONDecoder().decode(PullRequest.self, from: Data(json.utf8))
  }

  let refs = [
    ("zeta", 300.0 as TimeInterval?), ("alpha", 100), ("Beta", nil), ("gamma", 200),
  ].map { Self.ref($0.0, date: $0.1) }

  @Test func nameOrderIgnoresCase() {
    let names = BranchSort.name.sorted(refs, pullRequest: { _ in nil }, forkDate: { _ in nil }).map(\.shortName)
    #expect(names == ["alpha", "Beta", "gamma", "zeta"])
  }

  @Test func pullRequestsComeFirstThenName() throws {
    let pr = try pullRequest("gamma")
    let names = BranchSort.pullRequest
      .sorted(refs, pullRequest: { ["gamma", "zeta"].contains($0.shortName) ? pr : nil }, forkDate: { _ in nil })
      .map(\.shortName)
    #expect(names == ["gamma", "zeta", "alpha", "Beta"])
  }

  @Test func lastCommitNewestFirstUnknownLast() {
    let names = BranchSort.lastCommit.sorted(refs, pullRequest: { _ in nil }, forkDate: { _ in nil }).map(\.shortName)
    #expect(names == ["zeta", "gamma", "alpha", "Beta"])
  }

  @Test func forkDateUsesTheLookupAndBreaksTiesByName() {
    let forks: [String: Date] = ["alpha": Date(timeIntervalSince1970: 50), "zeta": Date(timeIntervalSince1970: 50), "Beta": Date(timeIntervalSince1970: 90)]
    let names = BranchSort.forkDate.sorted(refs, pullRequest: { _ in nil }, forkDate: { forks[$0.shortName] }).map(\.shortName)
    #expect(names == ["Beta", "alpha", "zeta", "gamma"])
  }
}
