import Foundation

public enum DiffLineKind: Sendable, Hashable {
  case context
  case added
  case removed
  case noNewline
}

public struct DiffLine: Sendable, Hashable, Identifiable {
  public let index: Int
  public let kind: DiffLineKind
  public let text: String
  public let oldLineNumber: Int?
  public let newLineNumber: Int?

  public var id: Int { index }

  public var prefix: Character {
    switch kind {
    case .context: " "
    case .added: "+"
    case .removed: "-"
    case .noNewline: "\\"
    }
  }

  public var rawLine: String { String(prefix) + text }
}

public struct Hunk: Sendable, Hashable, Identifiable {
  public let index: Int
  public let header: String
  public let oldStart: Int
  public let oldCount: Int
  public let newStart: Int
  public let newCount: Int
  public let lines: [DiffLine]

  public var id: Int { index }
  public var heading: String {
    guard let range = header.range(of: "@@", options: .backwards) else { return "" }
    return header[range.upperBound...].trimmingCharacters(in: .whitespaces)
  }

  public var patchText: String {
    ([header] + lines.map(\.rawLine)).joined(separator: "\n") + "\n"
  }
}

public struct FileDiff: Sendable, Hashable, Identifiable {
  public let oldPath: String?
  public let newPath: String?
  public let headerLines: [String]
  public let hunks: [Hunk]
  public let isBinary: Bool

  public var id: String { path }
  public var path: String { newPath ?? oldPath ?? "" }
  public var isNewFile: Bool { oldPath == nil }
  public var isDeletedFile: Bool { newPath == nil }
  public var isRename: Bool { oldPath != nil && newPath != nil && oldPath != newPath }

  public var headerText: String { headerLines.joined(separator: "\n") + "\n" }

  public func patch(for hunk: Hunk) -> String { headerText + hunk.patchText }
  public var fullPatch: String { headerText + hunks.map(\.patchText).joined() }
}

public enum DiffParser {
  public static func parse(_ text: String) -> [FileDiff] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let starts = lines.indices.filter { lines[$0].hasPrefix("diff --git ") }
    return zip(starts, starts.dropFirst() + [lines.count]).map { start, end in
      parseFile(Array(lines[start..<end]))
    }
  }

  private static func parseFile(_ lines: [String]) -> FileDiff {
    let firstHunk = lines.firstIndex { $0.hasPrefix("@@") } ?? lines.count
    let header = Array(lines[..<firstHunk]).filter { !$0.isEmpty }
    let (oldPath, newPath) = paths(from: header)
    let isBinary = header.contains { $0.hasPrefix("Binary files") || $0 == "GIT binary patch" }
    let hunkLines = Array(lines[firstHunk...])
    let hunkStarts = hunkLines.indices.filter { hunkLines[$0].hasPrefix("@@") }
    let hunks = zip(hunkStarts, hunkStarts.dropFirst() + [hunkLines.count]).enumerated().compactMap { index, bounds in
      parseHunk(index: index, lines: Array(hunkLines[bounds.0..<bounds.1]))
    }
    return FileDiff(
      oldPath: oldPath,
      newPath: newPath,
      headerLines: header.filter { !$0.hasPrefix("Binary files") },
      hunks: hunks,
      isBinary: isBinary
    )
  }

  private static func paths(from header: [String]) -> (String?, String?) {
    let old = header.first { $0.hasPrefix("--- ") }.map { String($0.dropFirst(4)) }
    let new = header.first { $0.hasPrefix("+++ ") }.map { String($0.dropFirst(4)) }
    if old != nil || new != nil {
      return (stripPrefix(old, "a/"), stripPrefix(new, "b/"))
    }
    return pathsFromGitLine(header.first ?? "")
  }

  private static func stripPrefix(_ path: String?, _ prefix: String) -> String? {
    guard let path, path != "/dev/null" else { return nil }
    let unquoted = path.hasPrefix("\"") ? unquote(path) : path
    return unquoted.hasPrefix(prefix) ? String(unquoted.dropFirst(prefix.count)) : unquoted
  }

  private static func unquote(_ quoted: String) -> String {
    var result = ""
    var escaped = false
    for char in quoted.dropFirst().dropLast() {
      if escaped {
        switch char {
        case "n": result.append("\n")
        case "t": result.append("\t")
        default: result.append(char)
        }
        escaped = false
      } else if char == "\\" {
        escaped = true
      } else {
        result.append(char)
      }
    }
    return result
  }

  private static func pathsFromGitLine(_ line: String) -> (String?, String?) {
    let body = line.dropFirst("diff --git ".count)
    guard let midpoint = body.range(of: " b/") else { return (nil, nil) }
    let old = String(body[body.index(body.startIndex, offsetBy: 2)..<midpoint.lowerBound])
    let new = String(body[midpoint.upperBound...])
    return (old, new)
  }

  private static func parseHunk(index: Int, lines: [String]) -> Hunk? {
    guard let header = lines.first, let ranges = parseHunkHeader(header) else { return nil }
    var oldLine = ranges.oldStart
    var newLine = ranges.newStart
    var parsed: [DiffLine] = []
    for raw in lines.dropFirst() {
      guard let prefix = raw.first else { continue }
      let text = String(raw.dropFirst())
      switch prefix {
      case " ":
        parsed.append(DiffLine(index: parsed.count, kind: .context, text: text, oldLineNumber: oldLine, newLineNumber: newLine))
        oldLine += 1
        newLine += 1
      case "+":
        parsed.append(DiffLine(index: parsed.count, kind: .added, text: text, oldLineNumber: nil, newLineNumber: newLine))
        newLine += 1
      case "-":
        parsed.append(DiffLine(index: parsed.count, kind: .removed, text: text, oldLineNumber: oldLine, newLineNumber: nil))
        oldLine += 1
      case "\\":
        parsed.append(DiffLine(index: parsed.count, kind: .noNewline, text: text, oldLineNumber: nil, newLineNumber: nil))
      default:
        continue
      }
    }
    return Hunk(
      index: index, header: header,
      oldStart: ranges.oldStart, oldCount: ranges.oldCount,
      newStart: ranges.newStart, newCount: ranges.newCount,
      lines: parsed
    )
  }

  private static func parseHunkHeader(_ header: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
    let parts = header.split(separator: " ")
    guard parts.count >= 3, let old = parseRange(parts[1], sign: "-"), let new = parseRange(parts[2], sign: "+") else {
      return nil
    }
    return (old.start, old.count, new.start, new.count)
  }

  private static func parseRange(_ text: Substring, sign: Character) -> (start: Int, count: Int)? {
    guard text.first == sign else { return nil }
    let numbers = text.dropFirst().split(separator: ",").compactMap { Int($0) }
    switch numbers.count {
    case 1: return (numbers[0], 1)
    case 2: return (numbers[0], numbers[1])
    default: return nil
    }
  }
}

public enum DiffTarget: Sendable, Hashable {
  case unstaged(path: String)
  case staged(path: String)
  case untracked(path: String)
  case commit(sha: String, path: String)
}

extension Git {
  static let diffOptions = ["--no-color", "--no-ext-diff", "--no-renames", "--unified=3"]

  public func unstagedDiff(paths: [String] = []) async throws -> [FileDiff] {
    let output = try await text(["diff"] + Self.diffOptions + ["--"] + paths)
    return DiffParser.parse(output)
  }

  public func stagedDiff(paths: [String] = []) async throws -> [FileDiff] {
    let output = try await text(["diff", "--cached"] + Self.diffOptions + ["--"] + paths)
    return DiffParser.parse(output)
  }

  public func untrackedDiff(path: String) async throws -> FileDiff? {
    let output = try await run(
      ["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "/dev/null", path],
      allowedExitCodes: [0, 1]
    )
    return DiffParser.parse(output.text).first
  }

  public func commitDiff(sha: String) async throws -> [FileDiff] {
    let output = try await text(
      ["show", "--format=", "--no-color", "--no-ext-diff", "-m", "--first-parent", "--find-renames", "--unified=3", sha, "--"]
    )
    return DiffParser.parse(output)
  }

  public func fileContent(revision: String, path: String) async throws -> String? {
    let output = try await run(["show", "\(revision):\(path)"], allowedExitCodes: [0, 128])
    return output.exitCode == 0 ? output.text : nil
  }

  public func indexContent(path: String) async throws -> String? {
    try await fileContent(revision: "", path: path)
  }

  public func workingTreeContent(path: String) throws -> String? {
    let url = workingDirectory.appendingPathComponent(path)
    guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}

extension DiffLine {
  func with(kind: DiffLineKind, index: Int) -> DiffLine {
    DiffLine(index: index, kind: kind, text: text, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber)
  }
}

extension Hunk {
  /// A hunk that applies only the selected changed lines: unselected additions disappear, unselected
  /// removals stay in the file as context. Nil when nothing selected is a change.
  public func selecting(lines selected: Set<Int>) -> Hunk? {
    var kept: [DiffLine] = []
    var previousKept = false
    for line in lines {
      switch line.kind {
      case .context:
        kept.append(line.with(kind: .context, index: kept.count))
        previousKept = true
      case .added:
        previousKept = selected.contains(line.index)
        if previousKept { kept.append(line.with(kind: .added, index: kept.count)) }
      case .removed:
        kept.append(line.with(kind: selected.contains(line.index) ? .removed : .context, index: kept.count))
        previousKept = true
      case .noNewline:
        if previousKept { kept.append(line.with(kind: .noNewline, index: kept.count)) }
      }
    }
    guard kept.contains(where: { $0.kind == .added || $0.kind == .removed }) else { return nil }
    return Hunk.rebuilt(index: index, heading: heading, oldStart: oldStart, newStart: newStart, lines: kept)
  }

  /// The same change seen from the other side: additions become removals and vice versa.
  public func reversed() -> Hunk {
    let flipped = lines.map { line -> DiffLine in
      switch line.kind {
      case .added: line.with(kind: .removed, index: line.index)
      case .removed: line.with(kind: .added, index: line.index)
      case .context, .noNewline: line
      }
    }
    return Hunk.rebuilt(index: index, heading: heading, oldStart: newStart, newStart: oldStart, lines: flipped)
  }

  static func rebuilt(index: Int, heading: String, oldStart: Int, newStart: Int, lines: [DiffLine]) -> Hunk {
    let oldCount = lines.filter { $0.kind == .context || $0.kind == .removed }.count
    let newCount = lines.filter { $0.kind == .context || $0.kind == .added }.count
    let header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" + (heading.isEmpty ? "" : " " + heading)
    return Hunk(index: index, header: header, oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: lines)
  }

  public var changedLineIndices: [Int] {
    lines.filter { $0.kind == .added || $0.kind == .removed }.map(\.index)
  }
}

extension FileDiff {
  /// Header for a patch that applies part of this file's change. A partial change never deletes the
  /// file, and a reversed partial change of a deleted file re-creates it, so the mode lines are chosen
  /// from the lines that survive rather than copied from the original diff.
  public func partialPatch(_ hunk: Hunk, reverse: Bool) -> String {
    let createsFile = reverse ? isDeletedFile : isNewFile
    let name = path
    let mode = headerLines.lazy.compactMap { line -> String? in
      for prefix in ["new file mode ", "deleted file mode "] where line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
      return nil
    }.first ?? "100644"
    var header = ["diff --git a/\(name) b/\(name)"]
    if createsFile {
      header.append("new file mode \(mode)")
      header.append("--- /dev/null")
    } else {
      header.append("--- a/\(name)")
    }
    header.append("+++ b/\(name)")
    return header.joined(separator: "\n") + "\n" + hunk.patchText
  }
}
