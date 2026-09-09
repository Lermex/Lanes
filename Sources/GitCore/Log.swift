import Foundation

public struct Commit: Sendable, Hashable, Identifiable {
  public let sha: String
  public let parents: [String]
  public let authorName: String
  public let authorEmail: String
  public let authorDate: Date
  public let committerDate: Date
  public let decorations: [String]
  public let subject: String
  public let body: String

  public var id: String { sha }
  public var shortSha: String { String(sha.prefix(8)) }
  public var isMerge: Bool { parents.count > 1 }

  public init(
    sha: String, parents: [String], authorName: String, authorEmail: String, authorDate: Date,
    committerDate: Date, decorations: [String], subject: String, body: String
  ) {
    self.sha = sha
    self.parents = parents
    self.authorName = authorName
    self.authorEmail = authorEmail
    self.authorDate = authorDate
    self.committerDate = committerDate
    self.decorations = decorations
    self.subject = subject
    self.body = body
  }
}

public enum LogParser {
  static let record: Character = "\u{1e}"
  static let field: Character = "\u{1f}"
  public static let format = "%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%ct%x1f%D%x1f%s%x1f%b"

  public static func parse(_ output: String) -> [Commit] {
    output.split(separator: record, omittingEmptySubsequences: true).compactMap(parseRecord)
  }

  private static func parseRecord(_ record: Substring) -> Commit? {
    let fields = record.split(separator: field, maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
    guard fields.count == 9, let authorTime = TimeInterval(fields[4]), let commitTime = TimeInterval(fields[5]) else {
      return nil
    }
    return Commit(
      sha: fields[0],
      parents: fields[1].split(separator: " ").map(String.init),
      authorName: fields[2],
      authorEmail: fields[3],
      authorDate: Date(timeIntervalSince1970: authorTime),
      committerDate: Date(timeIntervalSince1970: commitTime),
      decorations: parseDecorations(fields[6]),
      subject: fields[7],
      body: fields[8].trimmingCharacters(in: .newlines)
    )
  }

  static func parseDecorations(_ raw: String) -> [String] {
    raw.split(separator: ", ").flatMap { item -> [String] in
      let text = String(item)
      if text.hasPrefix("HEAD -> ") { return ["HEAD", String(text.dropFirst("HEAD -> ".count))] }
      if text.hasPrefix("tag: ") { return [String(text.dropFirst("tag: ".count))] }
      return [text]
    }
  }
}

extension Git {
  public func log(revisions: [String], limit: Int) async throws -> [Commit] {
    let revs = revisions.isEmpty ? ["HEAD"] : revisions
    let output = try await text(
      ["log", "--date-order", "--format=\(LogParser.format)", "--max-count=\(limit)"] + revs + ["--"]
    )
    return LogParser.parse(output)
  }
}
