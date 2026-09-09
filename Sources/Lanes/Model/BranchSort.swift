import Foundation
import GitCore

enum BranchSort: String, CaseIterable, Identifiable {
  case name
  case pullRequest
  case forkDate
  case lastCommit

  var id: Self { self }

  var title: String {
    switch self {
    case .name: "Name"
    case .pullRequest: "Pull request"
    case .forkDate: "Fork date"
    case .lastCommit: "Last commit"
    }
  }

  /// Orders branches for the sidebar; dates sort newest first with unknown dates last, and every
  /// order falls back to the name so the list is stable.
  func sorted(_ refs: [Ref], pullRequest: (Ref) -> PullRequest?, forkDate: (Ref) -> Date?) -> [Ref] {
    let byName: (Ref, Ref) -> Bool = { $0.branchName.localizedStandardCompare($1.branchName) == .orderedAscending }
    switch self {
    case .name:
      return refs.sorted(by: byName)
    case .pullRequest:
      return refs.sorted { a, b in
        let aHas = pullRequest(a) != nil, bHas = pullRequest(b) != nil
        return aHas != bHas ? aHas : byName(a, b)
      }
    case .forkDate:
      return Self.sorted(refs, newestFirst: forkDate, tieBreak: byName)
    case .lastCommit:
      return Self.sorted(refs, newestFirst: \.committerDate, tieBreak: byName)
    }
  }

  private static func sorted(_ refs: [Ref], newestFirst date: (Ref) -> Date?, tieBreak: (Ref, Ref) -> Bool) -> [Ref] {
    refs.sorted { a, b in
      switch (date(a), date(b)) {
      case let (da?, db?) where da != db: da > db
      case (.some, .none): true
      case (.none, .some): false
      default: tieBreak(a, b)
      }
    }
  }
}
