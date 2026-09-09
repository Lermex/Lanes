import Foundation
import Testing
@testable import GitCore

@Suite struct GitIntegrationTests {
  struct Repo {
    let url: URL
    let git: Git
  }

  func makeRepo() async throws -> Repo {
    let url = FileManager.default.temporaryDirectory.appending(path: "lanes-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let git = Git(workingDirectory: url)
    try await git.run(["init", "-q", "-b", "master"])
    try await git.run(["config", "user.email", "test@example.com"])
    try await git.run(["config", "user.name", "Test"])
    try write(url, "a.txt", numbered(1...30))
    try await git.run(["add", "-A"])
    try await git.run(["commit", "-qm", "init"])
    return Repo(url: url, git: git)
  }

  func numbered(_ range: ClosedRange<Int>, changing: Set<Int> = []) -> String {
    range.map { changing.contains($0) ? "line \($0) changed" : "line \($0)" }.joined(separator: "\n") + "\n"
  }

  func write(_ root: URL, _ path: String, _ content: String) throws {
    try content.write(to: root.appending(path: path), atomically: true, encoding: .utf8)
  }

  @Test func stagesAndUnstagesOneHunkAtATime() async throws {
    let repo = try await makeRepo()
    try write(repo.url, "a.txt", numbered(1...30, changing: [2, 28]))
    let file = try #require(try await repo.git.unstagedDiff().first)
    #expect(file.hunks.count == 2)

    try await repo.git.stageHunk(file.hunks[0], of: file)
    let staged = try #require(try await repo.git.stagedDiff().first)
    let unstagedAfterStage = try await repo.git.unstagedDiff()
    let status = try await repo.git.status()
    #expect(staged.hunks.count == 1)
    #expect(staged.hunks[0].lines.contains { $0.text == "line 2 changed" })
    #expect(unstagedAfterStage.first?.hunks.count == 1)
    #expect(status.staged.map(\.kind) == [.modified])
    #expect(status.unstaged.map(\.kind) == [.modified])

    try await repo.git.unstageHunk(staged.hunks[0], of: staged)
    let stagedAfterUnstage = try await repo.git.stagedDiff()
    let unstagedAfterUnstage = try await repo.git.unstagedDiff()
    #expect(stagedAfterUnstage.isEmpty)
    #expect(unstagedAfterUnstage.first?.hunks.count == 2)
  }

  @Test func stagesAndUnstagesIndividualLines() async throws {
    let repo = try await makeRepo()
    var lines = (1...30).map { "line \($0)" }
    lines.insert(contentsOf: ["added A", "added B"], at: 10)
    lines[2] = "line 3 changed"
    try write(repo.url, "a.txt", lines.joined(separator: "\n") + "\n")
    let file = try #require(try await repo.git.unstagedDiff().first)
    let hunk = try #require(file.hunks.first { $0.lines.contains { $0.text == "added A" } })
    let addedA = try #require(hunk.lines.first { $0.text == "added A" })
    try await repo.git.stageLines([addedA.index], of: hunk, in: file)
    let indexed = try #require(try await repo.git.indexContent(path: "a.txt"))
    #expect(indexed.contains("added A") && !indexed.contains("added B"))

    let staged = try #require(try await repo.git.stagedDiff().first)
    let stagedHunk = try #require(staged.hunks.first { $0.lines.contains { $0.text == "added A" } })
    let stagedA = try #require(stagedHunk.lines.first { $0.text == "added A" })
    try await repo.git.unstageLines([stagedA.index], of: stagedHunk, in: staged)
    let afterUnstage = try await repo.git.stagedDiff()
    #expect(afterUnstage.isEmpty || !afterUnstage[0].hunks.contains { $0.lines.contains { $0.text == "added A" && $0.kind == .added } })
  }

  @Test func stagesIntentToAddFileThroughItsHunk() async throws {
    let repo = try await makeRepo()
    try write(repo.url, "new.txt", "hello\nworld\n")
    try await repo.git.run(["add", "-N", "new.txt"])
    let before = try await repo.git.status()
    #expect(before.unstaged.map(\.kind) == [.intentToAdd])

    let file = try #require(try await repo.git.unstagedDiff().first { $0.path == "new.txt" })
    #expect(file.isNewFile)
    try await repo.git.stageHunk(file.hunks[0], of: file)
    let after = try await repo.git.status()
    #expect(after.staged.map(\.kind) == [.added])
    #expect(after.unstaged.isEmpty)
  }

  @Test func untrackedFileDiffStageAndCommit() async throws {
    let repo = try await makeRepo()
    try write(repo.url, "u.txt", "x\ny\n")
    let status = try await repo.git.status()
    #expect(status.unstaged.map(\.kind) == [.untracked])
    let diff = try #require(try await repo.git.untrackedDiff(path: "u.txt"))
    #expect(diff.isNewFile)
    #expect(diff.hunks.first?.lines.map(\.text) == ["x", "y"])

    try await repo.git.stage(paths: ["u.txt"])
    try await repo.git.commit(message: "Add u", amend: false)
    let clean = try await repo.git.status()
    let log = try await repo.git.log(revisions: ["HEAD"], limit: 10)
    #expect(clean.isClean)
    #expect(log.map(\.subject) == ["Add u", "init"])
    let commitDiff = try await repo.git.commitDiff(sha: log[0].sha)
    #expect(commitDiff.map(\.path) == ["u.txt"])
    let content = try await repo.git.fileContent(revision: log[0].sha, path: "u.txt")
    #expect(content == "x\ny\n")
  }

  @Test func hidesNestedRepositoriesFromUntrackedFiles() async throws {
    let repo = try await makeRepo()
    let nested = repo.url.appending(path: "vendor-tool")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try await Git(workingDirectory: nested).run(["init", "-q"])
    try write(nested, "tool.txt", "x\n")
    try FileManager.default.createDirectory(at: repo.url.appending(path: "plain-dir"), withIntermediateDirectories: true)
    try write(repo.url.appending(path: "plain-dir"), "loose.txt", "y\n")
    let status = try await repo.git.status()
    #expect(status.unstaged.map(\.path) == ["plain-dir/loose.txt"])
  }

  @Test func mergeBaseAndCommitDates() async throws {
    let repo = try await makeRepo()
    let base = try await repo.git.text(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    try await repo.git.run(["checkout", "-qb", "feature"])
    try write(repo.url, "feature.txt", "feature\n")
    try await repo.git.run(["add", "-A"])
    try await repo.git.run(["commit", "-qm", "feature work"])
    try await repo.git.run(["checkout", "-q", "master"])
    try write(repo.url, "master.txt", "master\n")
    try await repo.git.run(["add", "-A"])
    try await repo.git.run(["commit", "-qm", "master work"])
    let featureTip = try await repo.git.text(["rev-parse", "feature"]).trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(try await repo.git.mergeBase("master", "feature") == base)
    let dates = try await repo.git.commitDates([base, featureTip])
    #expect(Set(dates.keys) == [base, featureTip])
    let refs = try await repo.git.refs()
    #expect(refs.first { $0.shortName == "feature" }?.committerDate == dates[featureTip])

    try await repo.git.run(["checkout", "-q", "--orphan", "island"])
    try await repo.git.run(["commit", "-qm", "unrelated", "--allow-empty"])
    #expect(try await repo.git.mergeBase("master", "island") == nil)
  }

  @Test func branchOperations() async throws {
    let repo = try await makeRepo()
    let remote = repo.url.deletingLastPathComponent().appending(path: "lanes-remote-\(UUID().uuidString).git")
    try await repo.git.run(["init", "-q", "--bare", remote.path])
    try await repo.git.run(["remote", "add", "origin", remote.path])

    try await repo.git.run(["branch", "feature"])
    try await repo.git.switchBranch("feature")
    #expect(try await repo.git.head().branch == "feature")
    try await repo.git.renameBranch("feature", to: "renamed")
    #expect(try await repo.git.head().branch == "renamed")

    try await repo.git.push(branch: "renamed", to: "origin", setUpstream: true)
    let pushed = try await repo.git.refs()
    #expect(pushed.contains { $0.shortName == "origin/renamed" })
    #expect(pushed.first { $0.shortName == "renamed" }?.upstream == "origin/renamed")

    try await repo.git.switchBranch("master")
    try await repo.git.deleteBranch("renamed", force: false)
    try await repo.git.switchToTrackingBranch("origin/renamed")
    #expect(try await repo.git.head().branch == "renamed")
    try write(repo.url, "extra.txt", "unmerged\n")
    try await repo.git.run(["add", "-A"])
    try await repo.git.run(["commit", "-qm", "unmerged work"])
    try await repo.git.switchBranch("master")
    await #expect(throws: GitError.self) { try await repo.git.deleteBranch("renamed", force: false) }
    do {
      try await repo.git.deleteBranch("renamed", force: false)
    } catch let error as GitError {
      #expect(error.isNotFullyMerged)
    }
    try await repo.git.deleteBranch("renamed", force: true)
    try await repo.git.deleteRemoteBranch("renamed", on: "origin")
    let remaining = try await repo.git.refs()
    #expect(remaining.map(\.shortName) == ["master"])
  }

  @Test func refsHeadAndDiscovery() async throws {
    let repo = try await makeRepo()
    try await repo.git.run(["branch", "feature"])
    try await repo.git.run(["tag", "v1"])
    let refs = try await repo.git.refs()
    let head = try await repo.git.head()
    #expect(refs.map(\.shortName).sorted() == ["feature", "master", "v1"])
    #expect(refs.first { $0.isHead }?.shortName == "master")
    #expect(head.branch == "master")
    let info = try await RepositoryDiscovery.discover(at: repo.url)
    #expect(info.workTree.resolvingSymlinksInPath().path == repo.url.resolvingSymlinksInPath().path)
    #expect(info.gitDir.lastPathComponent == ".git")
  }
}
