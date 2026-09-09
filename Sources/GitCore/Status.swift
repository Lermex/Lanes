import Foundation

public enum ChangeKind: String, Sendable, Hashable {
  case modified
  case added
  case deleted
  case renamed
  case copied
  case typeChanged
  case untracked
  case unmerged
  case intentToAdd

  public var symbol: String {
    switch self {
    case .modified: "M"
    case .added: "A"
    case .deleted: "D"
    case .renamed: "R"
    case .copied: "C"
    case .typeChanged: "T"
    case .untracked: "?"
    case .unmerged: "U"
    case .intentToAdd: "A"
    }
  }
}

public struct WorkingCopyChange: Sendable, Hashable, Identifiable {
  public enum Area: Sendable, Hashable { case staged, unstaged }

  public let path: String
  public let originalPath: String?
  public let kind: ChangeKind
  public let area: Area

  public var id: String { "\(area):\(path)" }
  public var fileName: String { (path as NSString).lastPathComponent }
  public var directory: String { (path as NSString).deletingLastPathComponent }

  public init(path: String, originalPath: String?, kind: ChangeKind, area: Area) {
    self.path = path
    self.originalPath = originalPath
    self.kind = kind
    self.area = area
  }
}

public struct WorkingCopyStatus: Sendable, Equatable {
  public let staged: [WorkingCopyChange]
  public let unstaged: [WorkingCopyChange]

  public var isClean: Bool { staged.isEmpty && unstaged.isEmpty }
  public var changeCount: Int { staged.count + unstaged.count }

  public static let empty = WorkingCopyStatus(staged: [], unstaged: [])
}

public enum StatusParser {
  public static func parse(_ data: Data) -> WorkingCopyStatus {
    let fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
    let entries = consume(fields[...])
    return WorkingCopyStatus(
      staged: entries.flatMap(\.staged),
      unstaged: entries.flatMap(\.unstaged)
    )
  }

  private struct Entry {
    var staged: [WorkingCopyChange] = []
    var unstaged: [WorkingCopyChange] = []
  }

  private static func consume(_ fields: ArraySlice<String>) -> [Entry] {
    var entries: [Entry] = []
    var index = fields.startIndex
    while index < fields.endIndex {
      let line = fields[index]
      index += 1
      switch line.first {
      case "1":
        entries.append(ordinary(line))
      case "2":
        guard index < fields.endIndex else { return entries }
        entries.append(renamed(line, originalPath: fields[index]))
        index += 1
      case "u":
        entries.append(unmerged(line))
      case "?":
        let path = String(line.dropFirst(2))
        entries.append(Entry(unstaged: [WorkingCopyChange(path: path, originalPath: nil, kind: .untracked, area: .unstaged)]))
      default:
        continue
      }
    }
    return entries
  }

  private static func ordinary(_ line: String) -> Entry {
    let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 9 else { return Entry() }
    return entry(xy: parts[1], path: parts[8], originalPath: nil)
  }

  private static func renamed(_ line: String, originalPath: String) -> Entry {
    let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 10 else { return Entry() }
    return entry(xy: parts[1], path: parts[9], originalPath: originalPath)
  }

  private static func unmerged(_ line: String) -> Entry {
    let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 11 else { return Entry() }
    return Entry(unstaged: [WorkingCopyChange(path: parts[10], originalPath: nil, kind: .unmerged, area: .unstaged)])
  }

  private static func entry(xy: String, path: String, originalPath: String?) -> Entry {
    let chars = Array(xy)
    guard chars.count == 2 else { return Entry() }
    let staged = kind(chars[0], inWorktree: false).map {
      [WorkingCopyChange(path: path, originalPath: originalPath, kind: $0, area: .staged)]
    } ?? []
    let unstaged = kind(chars[1], inWorktree: true).map {
      [WorkingCopyChange(path: path, originalPath: nil, kind: $0, area: .unstaged)]
    } ?? []
    return Entry(staged: staged, unstaged: unstaged)
  }

  private static func kind(_ code: Character, inWorktree: Bool) -> ChangeKind? {
    switch code {
    case "M": .modified
    case "A": inWorktree ? .intentToAdd : .added
    case "D": .deleted
    case "R": .renamed
    case "C": .copied
    case "T": .typeChanged
    default: nil
    }
  }
}

extension WorkingCopyStatus {
  /// git lists a nested repository as a single untracked `dir/` entry; those are noise in a staging view
  public func hidingNestedRepositories(in workTree: URL) -> WorkingCopyStatus {
    WorkingCopyStatus(
      staged: staged,
      unstaged: unstaged.filter { change in
        guard change.kind == .untracked, change.path.hasSuffix("/") else { return true }
        return !FileManager.default.fileExists(atPath: workTree.appending(path: change.path + ".git").path)
      }
    )
  }
}

extension Git {
  public func status() async throws -> WorkingCopyStatus {
    let output = try await run(["status", "--porcelain=v2", "-z", "--untracked-files=all", "--no-renames"])
    return StatusParser.parse(output.stdout).hidingNestedRepositories(in: workingDirectory)
  }
}
