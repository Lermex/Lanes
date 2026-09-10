import Foundation
import Testing
@testable import GitCore

@Suite struct LogParserTests {
  @Test func parsesRecordsWithDecorationsAndBodies() {
    let output = "\u{1e}aaa\u{1f}bbb ccc\u{1f}Ann\u{1f}ann@x.io\u{1f}1700000000\u{1f}1700000100\u{1f}HEAD -> master, origin/master, tag: v1\u{1f}Subject line\u{1f}Body one\n\nBody two\n"
      + "\u{1e}bbb\u{1f}\u{1f}Bob\u{1f}bob@x.io\u{1f}1600000000\u{1f}1600000000\u{1f}\u{1f}Root\u{1f}\n"
    let commits = LogParser.parse(output)
    #expect(commits.count == 2)
    #expect(commits[0].parents == ["bbb", "ccc"])
    #expect(commits[0].decorations == ["HEAD", "master", "origin/master", "v1"])
    #expect(commits[0].body == "Body one\n\nBody two")
    #expect(commits[0].subject == "Subject line")
    #expect(commits[1].parents.isEmpty)
    #expect(commits[1].decorations.isEmpty)
  }
}

@Suite struct RefParserTests {
  @Test func classifiesRefsAndPeelsTags() {
    let output = [
      "refs/heads/master\u{0}1111\u{0}\u{0}*\u{0}origin/master\u{0}1700000000\u{0}",
      "refs/heads/feature\u{0}2222\u{0}\u{0} \u{0}\u{0}1700000100\u{0}",
      "refs/remotes/origin/HEAD\u{0}1111\u{0}\u{0} \u{0}\u{0}1700000000\u{0}",
      "refs/remotes/origin/master\u{0}1111\u{0}\u{0} \u{0}\u{0}1700000000\u{0}",
      "refs/tags/v1\u{0}tagobj\u{0}3333\u{0} \u{0}\u{0}1700000900\u{0}1700000200",
    ].joined(separator: "\n") + "\n"
    let refs = RefParser.parse(output)
    #expect(refs.map(\.shortName) == ["master", "feature", "origin/master", "v1"])
    #expect(refs[0].isHead)
    #expect(refs[0].upstream == "origin/master")
    #expect(refs[2].kind == .remoteBranch)
    #expect(refs[2].remote == "origin")
    #expect(refs[2].branchName == "master")
    #expect(refs[3].target == "3333")
    #expect(refs[1].committerDate == Date(timeIntervalSince1970: 1_700_000_100))
    #expect(refs[3].committerDate == Date(timeIntervalSince1970: 1_700_000_200), "annotated tags use the peeled commit's date")
  }
}

@Suite struct StatusParserTests {
  @Test func splitsStagedUnstagedUntrackedAndIntentToAdd() {
    let raw = [
      "1 M. N... 100644 100644 100644 aaa bbb staged.txt",
      "1 .M N... 100644 100644 100644 aaa aaa unstaged.txt",
      "1 MM N... 100644 100644 100644 aaa bbb both.txt",
      "1 .A N... 000000 000000 100644 000 000 intent.txt",
      "1 D. N... 100644 000000 000000 aaa 000 gone.txt",
      "? new file.txt",
      "u UU N... 100644 100644 100644 100644 a b c conflict.txt",
    ].joined(separator: "\u{0}") + "\u{0}"
    let status = StatusParser.parse(Data(raw.utf8))
    #expect(status.staged.map(\.path) == ["staged.txt", "both.txt", "gone.txt"])
    #expect(status.staged.map(\.kind) == [.modified, .modified, .deleted])
    #expect(status.unstaged.map(\.path) == ["unstaged.txt", "both.txt", "intent.txt", "new file.txt", "conflict.txt"])
    #expect(status.unstaged.map(\.kind) == [.modified, .modified, .intentToAdd, .untracked, .unmerged])
  }
}

@Suite struct DiffParserTests {
  static let sample = """
    diff --git a/src/A.scala b/src/A.scala
    index 1111111..2222222 100644
    --- a/src/A.scala
    +++ b/src/A.scala
    @@ -1,3 +1,4 @@ object A
     line1
    -old2
    +new2
    +new3
     line4
    @@ -10,2 +11,2 @@
     ctx
    -x
    +y
    \\ No newline at end of file
    diff --git a/new.txt b/new.txt
    new file mode 100644
    index 0000000..3333333
    --- /dev/null
    +++ b/new.txt
    @@ -0,0 +1 @@
    +hello
    diff --git a/img.png b/img.png
    index 4444444..5555555 100644
    Binary files a/img.png and b/img.png differ

    """

  @Test func parsesFilesHunksAndLineNumbers() {
    let files = DiffParser.parse(Self.sample)
    #expect(files.count == 3)
    let first = files[0]
    #expect(first.path == "src/A.scala")
    #expect(first.hunks.count == 2)
    #expect(first.hunks[0].heading == "object A")
    #expect(first.hunks[0].lines.map(\.kind) == [.context, .removed, .added, .added, .context])
    #expect(first.hunks[0].lines.map(\.newLineNumber) == [1, nil, 2, 3, 4])
    #expect(first.hunks[0].lines.map(\.oldLineNumber) == [1, 2, nil, nil, 3])
    #expect(first.hunks[1].lines.last?.kind == .noNewline)
    #expect(files[1].isNewFile)
    #expect(files[1].path == "new.txt")
    #expect(files[2].isBinary)
  }

  @Test func hunkPatchRoundTripsTheOriginalText() {
    let files = DiffParser.parse(Self.sample)
    let patch = files[0].patch(for: files[0].hunks[0])
    #expect(patch == """
      diff --git a/src/A.scala b/src/A.scala
      index 1111111..2222222 100644
      --- a/src/A.scala
      +++ b/src/A.scala
      @@ -1,3 +1,4 @@ object A
       line1
      -old2
      +new2
      +new3
       line4

      """)
  }
}

@Suite struct GraphLayoutTests {
  func commit(_ sha: String, _ parents: [String]) -> Commit {
    Commit(
      sha: sha, parents: parents, authorName: "", authorEmail: "", authorDate: .distantPast,
      committerDate: .distantPast, decorations: [], subject: sha, body: ""
    )
  }

  @Test func linearHistoryStaysInOneLane() {
    let layout = GraphLayout.compute([commit("c", ["b"]), commit("b", ["a"]), commit("a", [])])
    #expect(layout.rows.map(\.nodeLane) == [0, 0, 0])
    #expect(layout.maxLaneCount == 1)
    #expect(layout.rows[0].outgoing == [GraphTransition(fromLane: 0, toLane: 0, colorIndex: 0, startsAtNode: true)])
    #expect(layout.rows[2].outgoing.isEmpty)
  }

  @Test func mergeOpensASecondLaneThatRejoinsAtTheBase() {
    // m merges f into base; f's parent is base
    let layout = GraphLayout.compute([commit("m", ["b", "f"]), commit("f", ["base"]), commit("b", ["base"]), commit("base", [])])
    #expect(layout.rows.map(\.nodeLane) == [0, 1, 0, 0])
    #expect(layout.maxLaneCount == 2)
    #expect(layout.rows[0].outgoing.contains(GraphTransition(fromLane: 0, toLane: 1, colorIndex: 1, startsAtNode: true)))
    // f continues in lane 1 while b is drawn, then bends into base at lane 0
    #expect(layout.rows[2].outgoing.contains(GraphTransition(fromLane: 1, toLane: 0, colorIndex: 1, startsAtNode: false)))
    #expect(layout.rows[3].incoming.count == 2)
  }

  @Test func independentBranchTipsGetTheirOwnLanes() {
    let layout = GraphLayout.compute([commit("x", ["a"]), commit("y", ["a"]), commit("a", [])])
    #expect(layout.rows.map(\.nodeLane) == [0, 1, 0])
    #expect(layout.rows[1].outgoing.contains(GraphTransition(fromLane: 1, toLane: 0, colorIndex: 1, startsAtNode: true)))
  }
}

@Suite struct PartialHunkTests {
  var hunk: Hunk { DiffParser.parse(DiffParserTests.sample)[0].hunks[0] }  // ctx, -old2, +new2, +new3, ctx

  @Test func keepsSelectedChangesAndTurnsUnselectedRemovalsIntoContext() throws {
    let partial = try #require(hunk.selecting(lines: [2]))  // only +new2
    #expect(partial.lines.map(\.rawLine) == [" line1", " old2", "+new2", " line4"])
    #expect(partial.header == "@@ -1,3 +1,4 @@ object A")
    let removalOnly = try #require(hunk.selecting(lines: [1]))
    #expect(removalOnly.lines.map(\.rawLine) == [" line1", "-old2", " line4"])
    #expect(hunk.selecting(lines: [0, 4]) == nil)
  }

  @Test func reversedSwapsSidesAndPartialUnstageKeepsUnselectedAdditions() throws {
    let reversed = hunk.reversed()
    #expect(reversed.lines.map(\.rawLine) == [" line1", "+old2", "-new2", "-new3", " line4"])
    #expect(reversed.header == "@@ -1,4 +1,3 @@ object A")
    // unstaging only new3: new2 must stay in the index, so it becomes context
    let partial = try #require(reversed.selecting(lines: [3]))
    #expect(partial.lines.map(\.rawLine) == [" line1", " new2", "-new3", " line4"])
  }

  @Test func partialPatchHeaderNeverDeletesAndRecreatesOnReverse() {
    let files = DiffParser.parse(DiffParserTests.sample)
    let modified = files[0].partialPatch(files[0].hunks[0], reverse: false)
    #expect(modified.hasPrefix("diff --git a/src/A.scala b/src/A.scala\n--- a/src/A.scala\n+++ b/src/A.scala\n@@"))
    let created = files[1].partialPatch(files[1].hunks[0], reverse: false)
    #expect(created.contains("new file mode 100644\n--- /dev/null\n+++ b/new.txt"))
    let unstagedNewFile = files[1].partialPatch(files[1].hunks[0].reversed(), reverse: true)
    #expect(unstagedNewFile.contains("--- a/new.txt\n+++ b/new.txt"))
  }
}

@Suite struct RemoteWebURLTests {
  @Test func convertsFetchURLsToBrowsableOnes() {
    #expect(RemoteWebURL.webURL(for: "git@github.com:Lermex/Lanes.git")?.absoluteString == "https://github.com/Lermex/Lanes")
    #expect(RemoteWebURL.webURL(for: "https://github.com/Lermex/Lanes.git\n")?.absoluteString == "https://github.com/Lermex/Lanes")
    #expect(RemoteWebURL.webURL(for: "ssh://git@github.com/Lermex/Lanes")?.absoluteString == "https://github.com/Lermex/Lanes")
    #expect(RemoteWebURL.webURL(for: "/Users/x/repo.git") == nil)
  }
}

@Suite struct GitEnvironmentTests {
  @Test func routesPromptsToAskpassAndFillsAgentSocket() {
    let helper = URL(fileURLWithPath: "/Applications/Lanes.app/Contents/Resources/askpass.sh")
    let environment = Git.environment(base: ["PATH": "/usr/bin"], askpass: helper, agentSocket: "/tmp/agent.sock")
    #expect(environment["SSH_ASKPASS"] == helper.path)
    #expect(environment["GIT_ASKPASS"] == helper.path)
    #expect(environment["SSH_ASKPASS_REQUIRE"] == "force")
    #expect(environment["SSH_AUTH_SOCK"] == "/tmp/agent.sock")
    #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
    #expect(environment["PATH"] == "/usr/bin")
  }

  @Test func keepsAnExistingAgentSocket() {
    let environment = Git.environment(base: ["SSH_AUTH_SOCK": "/existing"], askpass: nil, agentSocket: "/tmp/agent.sock")
    #expect(environment["SSH_AUTH_SOCK"] == "/existing")
    #expect(environment["SSH_ASKPASS"] == nil)
  }
}
