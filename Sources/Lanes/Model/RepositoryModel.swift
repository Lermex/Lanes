import Foundation
import GitCore
import Highlighting
import Observation

enum HistorySelection: Hashable {
  case workingCopy
  case commit(String)
  case branch(String)
}

enum ViewMode: Hashable {
  case history
  case changes
}

enum DiffSource: Hashable {
  case change(WorkingCopyChange)
  case commitFile(sha: String, path: String)
}

@MainActor
@Observable
final class RepositoryModel {
  let info: RepositoryInfo
  let git: Git

  private(set) var refs: [Ref] = [] {
    didSet {
      refIndex = RefIndex(refs: refs)
      updateTrunkRef()
      updateBranchesWithPullRequests()
      sortedBranchesCache = [:]
    }
  }
  @ObservationIgnored private var refIndex = RefIndex(refs: [])
  private(set) var head = HeadState(sha: nil, branch: nil)
  private(set) var commits: [Commit] = []
  private(set) var graph = GraphLayout.empty
  private(set) var status = WorkingCopyStatus.empty
  private(set) var unstagedDiffs: [String: FileDiff] = [:]
  private(set) var stagedDiffs: [String: FileDiff] = [:]
  private(set) var untrackedDiffs: [String: FileDiff] = [:]
  private(set) var commitDiffs: [String: [FileDiff]] = [:]
  private(set) var presentations: [DiffPresentation.Key: DiffPresentation] = [:]
  private(set) var presentationGeneration = 0
  private(set) var isRefreshing = false
  private(set) var isBusy = false
  private(set) var historyTruncated = false
  private(set) var pullRequests: [String: PullRequest] = [:] {
    didSet {
      updateBranchesWithPullRequests()
      sortedBranchesCache = [:]
    }
  }
  /// Date of each branch's fork point from the trunk, keyed by ref full name.
  private(set) var forkDates: [String: Date] = [:] {
    didSet { sortedBranchesCache = [:] }
  }
  private(set) var trunkRef: Ref?
  private(set) var branchesWithPullRequests: [Ref] = []
  @ObservationIgnored private var sortedBranchesCache: [String: [Ref]] = [:]
  private(set) var trunkLayout: TrunkLayout?
  var errorMessage: String?
  var mode: ViewMode = .history

  // Dialog requests shared by the sidebar and history context menus; RepositoryDialogs presents them.
  var branchToRename: Ref?
  var branchToDelete: Ref?
  var branchToForceDelete: Ref?
  var commitForNewBranch: Commit?
  var commitToTag: Commit?
  var commitToResetTo: Commit?
  private(set) var originWebURL: URL?

  var filter: BranchFilter {
    didSet {
      guard filter != oldValue else { return }
      BranchFilterStore.save(filter, for: info)
      updateBranchesWithPullRequests()
      scheduleHistoryReload()
    }
  }
  var trunkView: TrunkViewSettings {
    didSet {
      guard trunkView != oldValue else { return }
      TrunkViewStore.save(trunkView, for: info)
      updateTrunkRef()
      if trunkView.trunk != oldValue.trunk {
        scheduleHistoryReload()
        scheduleForkDates()
      } else {
        recomputeTrunkLayout()
      }
    }
  }
  var selection: HistorySelection?
  var selectedChangeIDs: Set<WorkingCopyChange.ID> = []
  var selectedChangeID: WorkingCopyChange.ID? {
    get { selectedChangeIDs.count == 1 ? selectedChangeIDs.first : nil }
    set { selectedChangeIDs = newValue.map { [$0] } ?? [] }
  }
  var selectedCommitPath: String?
  var commitMessage = ""
  var amend = false {
    didSet { if amend, commitMessage.isEmpty { Task { await prefillAmendMessage() } } }
  }

  private var commitLimit = 1500
  private var watcher: RepositoryWatcher?
  private var pendingRefresh: Task<Void, Never>?
  private var pendingHistoryReload: Task<Void, Never>?
  @ObservationIgnored private var forkDatesTask: Task<Void, Never>?
  /// merge-base results keyed by "<trunk sha> <tip sha>", so a refresh only asks git about new tips
  @ObservationIgnored private var forkPointCache: [String: String] = [:]
  private var pendingPresentations: Set<DiffPresentation.Key> = []
  private var lastPullRequestFetch: Date?
  private var lastHeadBranch: String?
  private var pullRequestsUnavailable = false

  init(info: RepositoryInfo) {
    self.info = info
    self.git = Git(workingDirectory: info.workTree)
    self.filter = BranchFilterStore.load(for: info)
    self.trunkView = TrunkViewStore.load(for: info)
    watcher = RepositoryWatcher(paths: [info.workTree, info.gitDir, info.commonGitDir]) { [weak self] paths in
      guard !paths.allSatisfy({ $0.hasSuffix(".lock") }) else { return }
      Task { @MainActor [weak self] in self?.scheduleRefresh() }
    }
  }

  func setShowAll(_ showAll: Bool) {
    var updated = filter
    updated.showAll = showAll
    if !showAll, updated.selected.isEmpty {
      updated.selected = Set(refs.filter { $0.kind != .tag }.map(\.fullName))
    }
    filter = updated
  }

  // MARK: Trunk view

  private func updateTrunkRef() {
    trunkRef = resolveTrunkRef()
  }

  private func resolveTrunkRef() -> Ref? {
    if let chosen = trunkView.trunk, let ref = refs.first(where: { $0.fullName == chosen }) { return ref }
    let candidates = ["refs/remotes/origin/master", "refs/remotes/origin/main"]
    if let preferred = refs.first(where: { candidates.contains($0.fullName) }) { return preferred }
    if let anyRemote = refs.first(where: { $0.kind == .remoteBranch && ["master", "main"].contains($0.branchName) }) {
      return anyRemote
    }
    return refs.first { $0.kind == .localBranch && ["master", "main"].contains($0.shortName) }
  }

  var isTrunkViewActive: Bool { trunkView.enabled && trunkLayout != nil }

  func setTrunk(_ ref: Ref) { trunkView.trunk = ref.fullName }

  func toggleGroup(_ id: String) {
    if trunkView.expanded.contains(id) { trunkView.expanded.remove(id) } else { trunkView.expanded.insert(id) }
  }

  func expandAllGroups() {
    trunkView.expanded = Set(trunkLayout?.groups.map(\.id) ?? [])
  }

  func collapseAllGroups() {
    trunkView.expanded = []
  }

  private func recomputeTrunkLayout() {
    guard trunkView.enabled, let trunk = trunkRef else {
      trunkLayout = nil
      return
    }
    let hidden = filter.hiddenRemotes
    let tips = refs
      .filter { $0.fullName != trunk.fullName && !($0.remote.map(hidden.contains) ?? false) }
      .map { ref in
        TrunkTip(
          fullName: ref.fullName, shortName: ref.shortName, sha: ref.target, isHead: ref.isHead,
          priority: ref.kind == .localBranch ? 0 : ref.kind == .remoteBranch ? 1 : 2
        )
      }
    let commits = self.commits
    let expanded = trunkView.expanded
    let trunkSha = trunk.target
    Task {
      let layout = await Task.detached { TrunkLayout.compute(commits: commits, trunkSha: trunkSha, tips: tips, expanded: expanded) }.value
      guard self.commits == commits else { return }
      trunkLayout = layout
    }
  }

  private func expandCheckedOutBranchIfChanged() {
    guard head.branch != lastHeadBranch else { return }
    lastHeadBranch = head.branch
    if let branch = head.branch { trunkView.expanded.insert("refs/heads/\(branch)") }
  }

  // MARK: Derived state

  var localBranches: [Ref] { refIndex.localBranches }
  var allRemoteNames: [String] { refIndex.remoteNames }
  var remoteNames: [String] { allRemoteNames.filter { !filter.hiddenRemotes.contains($0) } }
  var hiddenRemoteNames: [String] { allRemoteNames.filter { filter.hiddenRemotes.contains($0) } }

  func setRemoteHidden(_ remote: String, _ hidden: Bool) {
    if hidden { filter.hiddenRemotes.insert(remote) } else { filter.hiddenRemotes.remove(remote) }
  }

  private func updateBranchesWithPullRequests() {
    branchesWithPullRequests = refs.filter { $0.kind != .tag && !filter.isRemoteHidden($0) && pullRequest(for: $0) != nil }
  }

  func sortedLocalBranches(by sort: BranchSort) -> [Ref] {
    cachedSort("local \(sort.rawValue)") { sort.sorted(localBranches, pullRequest: pullRequest(for:), forkDate: { forkDates[$0.fullName] }) }
  }

  func sortedRemoteBranches(_ remote: String, by sort: BranchSort) -> [Ref] {
    cachedSort("remote \(remote) \(sort.rawValue)") {
      sort.sorted(remoteBranches(remote), pullRequest: pullRequest(for:), forkDate: { forkDates[$0.fullName] })
    }
  }

  private func cachedSort(_ key: String, _ compute: () -> [Ref]) -> [Ref] {
    if let cached = sortedBranchesCache[key] { return cached }
    let sorted = compute()
    sortedBranchesCache[key] = sorted
    return sorted
  }

  func selectNoBranches() {
    replaceSelection(with: [])
  }

  func selectLocalBranches() {
    replaceSelection(with: Set(localBranches.map(\.fullName)))
  }

  func selectBranchesWithPullRequests() {
    let withPullRequests = Set(branchesWithPullRequests.map(\.fullName))
    var updated = filter
    updated.selected = updated.showAll ? withPullRequests : updated.selected.union(withPullRequests)
    updated.showAll = false
    filter = updated
  }

  private func replaceSelection(with selected: Set<String>) {
    var updated = filter
    updated.selected = selected
    updated.showAll = false
    filter = updated
  }

  func isDecorationVisible(_ decoration: String) -> Bool {
    let remote = allRemoteNames.first { decoration.hasPrefix($0 + "/") }
    guard let remote else { return true }
    return decoration != remote + "/HEAD" && !filter.hiddenRemotes.contains(remote)
  }

  func pullRequest(for ref: Ref) -> PullRequest? {
    pullRequests[ref.branchName]
  }

  // MARK: Fork dates

  private func scheduleForkDates() {
    forkDatesTask?.cancel()
    guard let trunk = trunkRef else {
      forkDates = [:]
      return
    }
    let trunkSha = trunk.target
    let branches = refs.filter { $0.kind != .tag }
    let cache = forkPointCache
    let git = git
    forkDatesTask = Task { [weak self] in
      var forkPoints: [String: String] = [:]
      var pending: [Ref] = []
      for ref in branches {
        if let known = cache["\(trunkSha) \(ref.target)"] { forkPoints[ref.fullName] = known } else { pending.append(ref) }
      }
      let computed = await Self.mergeBases(of: pending, with: trunkSha, git: git)
      var updatedCache = cache
      for ref in pending {
        guard let sha = computed[ref.fullName] else { continue }
        forkPoints[ref.fullName] = sha
        updatedCache["\(trunkSha) \(ref.target)"] = sha
      }
      let dates = (try? await git.commitDates(Array(Set(forkPoints.values)))) ?? [:]
      guard !Task.isCancelled, let self else { return }
      forkPointCache = updatedCache
      forkDates = forkPoints.compactMapValues { dates[$0] }
    }
  }

  nonisolated private static func mergeBases(of refs: [Ref], with trunkSha: String, git: Git) async -> [String: String] {
    await withTaskGroup(of: (String, String?).self) { group in
      var results: [String: String] = [:]
      var next = 0
      for _ in 0..<min(8, refs.count) {
        let ref = refs[next]
        next += 1
        group.addTask { (ref.fullName, try? await git.mergeBase(trunkSha, ref.target)) }
      }
      for await (name, sha) in group {
        if let sha { results[name] = sha }
        if next < refs.count {
          let ref = refs[next]
          next += 1
          group.addTask { (ref.fullName, try? await git.mergeBase(trunkSha, ref.target)) }
        }
      }
      return results
    }
  }

  func pullRequest(forBranchName name: String) -> PullRequest? {
    if let direct = pullRequests[name] { return direct }
    guard let remote = refIndex.remoteNames.first(where: { name.hasPrefix($0 + "/") }) else { return nil }
    return pullRequests[String(name.dropFirst(remote.count + 1))]
  }

  func remoteBranches(_ remote: String) -> [Ref] { refIndex.remoteBranches[remote] ?? [] }
  func ref(named shortName: String) -> Ref? { refIndex.byShortName[shortName] }
  var tags: [Ref] { refIndex.tags }
  var refKinds: [String: RefKind] { refIndex.kinds }

  var allChanges: [WorkingCopyChange] { status.staged + status.unstaged }

  var selectedChange: WorkingCopyChange? {
    allChanges.first { $0.id == selectedChangeID }
  }

  var selectedChanges: [WorkingCopyChange] {
    allChanges.filter { selectedChangeIDs.contains($0.id) }
  }

  var selectedCommit: Commit? {
    guard case .commit(let sha) = selection else { return nil }
    return commits.first { $0.sha == sha }
  }

  func diff(for change: WorkingCopyChange) -> FileDiff? {
    switch (change.area, change.kind) {
    case (.staged, _): stagedDiffs[change.path]
    case (.unstaged, .untracked): untrackedDiffs[change.path]
    case (.unstaged, _): unstagedDiffs[change.path]
    }
  }

  func diff(forCommit sha: String, path: String) -> FileDiff? {
    commitDiffs[sha]?.first { $0.path == path }
  }

  // MARK: Refreshing

  func scheduleRefresh() {
    pendingRefresh?.cancel()
    pendingRefresh = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await self?.refresh()
    }
  }

  func refresh(force: Bool = false) async {
    isRefreshing = true
    defer { isRefreshing = false }
    let pullRequestsStale = lastPullRequestFetch.map { Date().timeIntervalSince($0) > 60 } ?? true
    if force || (pullRequestsStale && !pullRequestsUnavailable) {
      Task { await refreshPullRequests() }
    }
    do {
      async let refs = git.refs()
      async let head = git.head()
      async let status = git.status()
      async let unstaged = git.unstagedDiff()
      async let staged = git.stagedDiff()
      self.refs = try await refs
      self.head = try await head
      if originWebURL == nil, let remote = try await git.remoteURL("origin") { originWebURL = RemoteWebURL.webURL(for: remote) }
      self.status = try await status
      unstagedDiffs = Self.byPath(try await unstaged)
      stagedDiffs = Self.byPath(try await staged)
      untrackedDiffs = [:]
      pruneStalePresentations()
      expandCheckedOutBranchIfChanged()
      scheduleForkDates()
      try await reloadHistory()
      reconcileSelection()
      errorMessage = nil
      debugLog(stateSummary)
    } catch {
      report(error)
    }
  }

  private var stateSummary: String {
    let lanes = graph.rows.map { String($0.nodeLane) }.joined()
    return "refresh: refs=\(refs.count) head=\(head.branch ?? "detached") commits=\(commits.count) maxLanes=\(graph.maxLaneCount) "
      + "nodeLanes=\(lanes) staged=\(status.staged.map(\.path)) unstaged=\(status.unstaged.map { "\($0.kind.symbol) \($0.path)" }) "
      + "unstagedDiffs=\(unstagedDiffs.keys.sorted()) stagedDiffs=\(stagedDiffs.keys.sorted()) selection=\(String(describing: selection))"
  }

  private func refreshPullRequests() async {
    lastPullRequestFetch = Date()
    do {
      let list = try await GitHubCLI.openPullRequests(workTree: info.workTree)
      pullRequests = Dictionary(list.map { ($0.headRefName, $0) }, uniquingKeysWith: { first, _ in first })
      pullRequestsUnavailable = false
    } catch {
      pullRequestsUnavailable = true
      debugLog("pull requests unavailable: \(error)")
    }
  }

  private func scheduleHistoryReload() {
    pendingHistoryReload?.cancel()
    pendingHistoryReload = Task { [weak self] in
      guard let self else { return }
      do { try await reloadHistory() } catch { report(error) }
    }
  }

  private func reloadHistory() async throws {
    let revisions = filter.revisions(refs: refs) + (trunkRef.map { [$0.fullName] } ?? [])
    let limit = commitLimit
    let loaded = try await git.log(revisions: revisions, limit: limit)
    let layout = await Task.detached { GraphLayout.compute(loaded) }.value
    commits = loaded
    graph = layout
    historyTruncated = loaded.count >= limit
    recomputeTrunkLayout()
    if case .commit(let sha) = selection, !loaded.contains(where: { $0.sha == sha }) {
      selection = nil
    }
  }

  func fitGraphColumn() {
    UserDefaults.standard.set(0.0, forKey: HistoryColumnWidths.graphKey)
  }

  func loadMoreHistory() {
    commitLimit += 1500
    scheduleHistoryReload()
  }

  private func reconcileSelection() {
    if selection == nil {
      selection = status.isClean ? commits.first.map { .commit($0.sha) } : .workingCopy
    }
    if selection == .workingCopy, status.isClean {
      selection = commits.first.map { .commit($0.sha) }
    }
    let existing = Set(allChanges.map(\.id))
    let surviving = selectedChangeIDs.intersection(existing)
    if surviving.isEmpty, let lost = selectedChangeIDs.first {
      let area: WorkingCopyChange.Area = lost.hasPrefix("staged") ? .staged : .unstaged
      let candidates = area == .staged ? status.staged : status.unstaged
      selectedChangeIDs = (candidates.first ?? status.unstaged.first ?? status.staged.first).map { [$0.id] } ?? []
    } else if surviving != selectedChangeIDs {
      selectedChangeIDs = surviving
    }
    if selectedChangeIDs.isEmpty, let first = status.unstaged.first ?? status.staged.first {
      selectedChangeIDs = [first.id]
    }
  }

  // a presentation stays valid while its diff is unchanged; views re-request after every refresh, which
  // is a no-op when the presentation survived and a rebuild when the diff moved on
  private func pruneStalePresentations() {
    let live = Set((Array(unstagedDiffs.values) + Array(stagedDiffs.values)).map(\.hashValue))
    presentations = presentations.filter { $0.key.isImmutable || live.contains($0.key.fileIdentity) }
    presentationGeneration += 1
  }

  private static func byPath(_ diffs: [FileDiff]) -> [String: FileDiff] {
    Dictionary(diffs.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
  }

  // MARK: Lazy loading

  func ensureUntrackedDiff(path: String) async {
    guard untrackedDiffs[path] == nil else { return }
    do {
      if let diff = try await git.untrackedDiff(path: path) {
        untrackedDiffs[path] = diff
      }
    } catch {
      report(error)
    }
  }

  func ensureCommitDiff(sha: String) async {
    guard commitDiffs[sha] == nil else { return }
    do {
      let diffs = try await git.commitDiff(sha: sha)
      commitDiffs[sha] = diffs
      if selectedCommitPath == nil || !diffs.contains(where: { $0.path == selectedCommitPath }) {
        selectedCommitPath = diffs.first?.path
      }
    } catch {
      report(error)
    }
  }

  func ensurePresentation(for source: DiffSource, file: FileDiff, theme: SyntaxTheme) async {
    let key = DiffPresentation.Key(source: source, file: file, theme: theme)
    guard presentations[key] == nil, !pendingPresentations.contains(key) else { return }
    pendingPresentations.insert(key)
    defer { pendingPresentations.remove(key) }
    let contents = await loadContents(for: source, file: file)
    let presentation = await Task.detached {
      DiffPresentation.build(key: key, file: file, oldText: contents.old, newText: contents.new, theme: theme)
    }.value
    presentations[key] = presentation
  }

  private func loadContents(for source: DiffSource, file: FileDiff) async -> (old: String?, new: String?) {
    switch source {
    case .change(let change) where change.area == .staged:
      return (await content(revision: "HEAD", path: file.oldPath), await content(revision: "", path: file.newPath))
    case .change(let change) where change.kind == .untracked:
      return (nil, try? git.workingTreeContent(path: change.path))
    case .change(let change):
      return (await content(revision: "", path: file.oldPath), try? git.workingTreeContent(path: change.path))
    case .commitFile(let sha, _):
      return (await content(revision: "\(sha)^", path: file.oldPath), await content(revision: sha, path: file.newPath))
    }
  }

  private func content(revision: String, path: String?) async -> String? {
    guard let path else { return nil }
    return (try? await git.fileContent(revision: revision, path: path)) ?? nil
  }

  // MARK: Actions

  func fetch() {
    perform(forceRefresh: true) { try await self.git.fetchAll() }
  }

  // MARK: Branch actions

  func switchTo(_ ref: Ref) {
    guard !ref.isHead else { return }
    perform {
      switch ref.kind {
      case .localBranch:
        try await self.git.switchBranch(ref.shortName)
      case .remoteBranch:
        if self.localBranches.contains(where: { $0.shortName == ref.branchName }) {
          try await self.git.switchBranch(ref.branchName)
        } else {
          try await self.git.switchToTrackingBranch(ref.shortName)
        }
      case .tag:
        return
      }
    }
  }

  /// Remotes a local branch can be pushed to: its upstream's remote when it has one, else every remote.
  func pushRemotes(for ref: Ref) -> [String] {
    guard ref.kind == .localBranch else { return [] }
    if let upstream = ref.upstream, let remote = allRemoteNames.first(where: { upstream.hasPrefix($0 + "/") }) {
      return [remote]
    }
    return allRemoteNames
  }

  func push(_ ref: Ref, to remote: String) {
    let setUpstream = ref.upstream == nil
    perform(forceRefresh: true) { try await self.git.push(branch: ref.shortName, to: remote, setUpstream: setUpstream) }
  }

  func rename(_ ref: Ref, to newName: String) {
    let name = newName.trimmingCharacters(in: .whitespaces)
    guard ref.kind == .localBranch, !name.isEmpty, name != ref.shortName else { return }
    perform {
      try await self.git.renameBranch(ref.shortName, to: name)
      let renamed = "refs/heads/\(name)"
      if self.filter.selected.remove(ref.fullName) != nil { self.filter.selected.insert(renamed) }
      if self.trunkView.trunk == ref.fullName { self.trunkView.trunk = renamed }
    }
  }

  // MARK: Commit actions

  func checkout(_ commit: Commit) {
    perform { try await self.git.checkoutDetached(commit.sha) }
  }

  func createBranch(named newName: String, at commit: Commit, switchTo: Bool) {
    let name = newName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    perform {
      try await self.git.createBranch(name, at: commit.sha, switchTo: switchTo)
      self.filter.selected.insert("refs/heads/\(name)")
    }
  }

  func createTag(named newName: String, at commit: Commit) {
    let name = newName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    perform { try await self.git.createTag(name, at: commit.sha) }
  }

  func cherryPick(_ commit: Commit) {
    perform { try await self.git.cherryPick(commit.sha) }
  }

  func revert(_ commit: Commit) {
    perform { try await self.git.revert(commit.sha) }
  }

  func reset(to commit: Commit, mode: ResetMode) {
    perform { try await self.git.reset(to: commit.sha, mode: mode) }
  }

  func webURL(for commit: Commit) -> URL? {
    originWebURL?.appending(path: "commit/\(commit.sha)")
  }

  /// Deletes a branch, remote branch or tag. Returns false when git refused a branch because it is
  /// not fully merged, so the caller can ask before forcing; every other failure is reported like
  /// any operation.
  func delete(_ ref: Ref, force: Bool) async -> Bool {
    guard !ref.isHead else { return true }
    isBusy = true
    defer { isBusy = false }
    do {
      switch ref.kind {
      case .localBranch: try await git.deleteBranch(ref.shortName, force: force)
      case .remoteBranch: if let remote = ref.remote { try await git.deleteRemoteBranch(ref.branchName, on: remote) }
      case .tag: try await git.deleteTag(ref.shortName)
      }
      filter.selected.remove(ref.fullName)
      await refresh(force: ref.kind == .remoteBranch)
    } catch let error as GitError where !force && error.isNotFullyMerged {
      return false
    } catch {
      report(error)
    }
    return true
  }

  func stage(_ change: WorkingCopyChange) { stage([change]) }
  func unstage(_ change: WorkingCopyChange) { unstage([change]) }

  func stage(_ changes: [WorkingCopyChange]) {
    let paths = changes.filter { $0.area == .unstaged && $0.kind != .unmerged }.map(\.path)
    guard !paths.isEmpty else { return }
    perform { try await self.git.stage(paths: paths) }
  }

  func unstage(_ changes: [WorkingCopyChange]) {
    let paths = changes.filter { $0.area == .staged }.map(\.path)
    guard !paths.isEmpty else { return }
    perform { try await self.git.unstage(paths: paths) }
  }

  func toggleStaged(_ changes: [WorkingCopyChange]) {
    let toStage = changes.filter { $0.area == .unstaged }
    let toUnstage = changes.filter { $0.area == .staged }
    guard !(toStage.isEmpty && toUnstage.isEmpty) else { return }
    perform {
      let stagePaths = toStage.filter { $0.kind != .unmerged }.map(\.path)
      let unstagePaths = toUnstage.map(\.path)
      if !stagePaths.isEmpty { try await self.git.stage(paths: stagePaths) }
      if !unstagePaths.isEmpty { try await self.git.unstage(paths: unstagePaths) }
    }
  }

  func toggleStagedSelection() { toggleStaged(selectedChanges) }

  func stageAll() {
    let paths = status.unstaged.filter { $0.kind != .unmerged }.map(\.path)
    guard !paths.isEmpty else { return }
    perform { try await self.git.stage(paths: paths) }
  }

  func unstageAll() {
    let paths = status.staged.map(\.path)
    guard !paths.isEmpty else { return }
    perform { try await self.git.unstage(paths: paths) }
  }

  func stageHunk(_ hunk: Hunk, of file: FileDiff) { perform { try await self.git.stageHunk(hunk, of: file) } }
  func stageLines(_ lines: Set<Int>, of hunk: Hunk, in file: FileDiff) { perform { try await self.git.stageLines(lines, of: hunk, in: file) } }
  func unstageLines(_ lines: Set<Int>, of hunk: Hunk, in file: FileDiff) { perform { try await self.git.unstageLines(lines, of: hunk, in: file) } }
  func unstageHunk(_ hunk: Hunk, of file: FileDiff) { perform { try await self.git.unstageHunk(hunk, of: file) } }

  func commit() {
    let message = commitMessage
    let amend = amend
    perform {
      try await self.git.commit(message: message, amend: amend)
      self.commitMessage = ""
      self.amend = false
    }
  }

  private func prefillAmendMessage() async {
    if let message = try? await git.lastCommitMessage() { commitMessage = message }
  }

  private func perform(forceRefresh: Bool = false, _ operation: @escaping @MainActor () async throws -> Void) {
    Task {
      isBusy = true
      defer { isBusy = false }
      do {
        try await operation()
        await refresh(force: forceRefresh)
      } catch {
        report(error)
      }
    }
  }

  private func report(_ error: Error) {
    errorMessage = (error as? GitError)?.description ?? error.localizedDescription
  }
}
