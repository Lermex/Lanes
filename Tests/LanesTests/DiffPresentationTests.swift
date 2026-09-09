import GitCore
import Highlighting
import Testing
@testable import Lanes

@Suite struct DiffPresentationTests {
  @Test func lineIdentitiesAreUniqueAcrossHunks() throws {
    let diff = """
      diff --git a/a.txt b/a.txt
      --- a/a.txt
      +++ b/a.txt
      @@ -1,3 +1,3 @@
       one
      -two
      +TWO
       three
      @@ -10,3 +10,3 @@
       ten
      -eleven
      +ELEVEN
       twelve
      """
    let file = try #require(DiffParser.parse(diff).first)
    let change = WorkingCopyChange(path: "a.txt", originalPath: nil, kind: .modified, area: .unstaged)
    let presentation = DiffPresentation.plain(source: .change(change), file: file, theme: .lanesDark)
    let ids = presentation.sections.flatMap { $0.lines.map(\.id) }
    #expect(ids.count == 8)
    #expect(Set(ids).count == ids.count)
  }
}
