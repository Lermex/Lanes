import GitCore

/// Lookups over the ref list that rows need on every render, built once per refresh.
struct RefIndex {
  let localBranches: [Ref]
  let remoteBranches: [String: [Ref]]
  let remoteNames: [String]
  let tags: [Ref]
  let kinds: [String: RefKind]

  init(refs: [Ref]) {
    localBranches = refs.filter { $0.kind == .localBranch }
    remoteBranches = Dictionary(grouping: refs.filter { $0.kind == .remoteBranch }) { $0.remote ?? "" }
    remoteNames = remoteBranches.keys.sorted()
    tags = refs.filter { $0.kind == .tag }
    kinds = Dictionary(refs.map { ($0.shortName, $0.kind) }, uniquingKeysWith: { first, _ in first })
  }
}
