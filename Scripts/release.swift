import Foundation

// release.swift next-version <last version> <patch|minor|major>
//   prints the version that follows the last one
// release.swift notes <last tag> <new version>
//   prints Markdown release notes: every commit since the last tag grouped by what it did, a compare
//   link, then the install instructions from $RELEASE_FOOTER (default .github/release-notes.md)

func git(_ arguments: [String]) -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["git"] + arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  try! process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return String(decoding: data, as: UTF8.self)
}

func nextVersion(after last: String, bump: String) -> String {
  guard !last.isEmpty else { return "0.1.0" }
  var parts = last.split(separator: ".").map { Int($0) ?? 0 }
  while parts.count < 3 { parts.append(0) }
  switch bump {
  case "major": return "\(parts[0] + 1).0.0"
  case "minor": return "\(parts[0]).\(parts[1] + 1).0"
  default: return "\(parts[0]).\(parts[1]).\(parts[2] + 1)"
  }
}

func repositoryURL() -> String? {
  let environment = ProcessInfo.processInfo.environment
  if let server = environment["GITHUB_SERVER_URL"], let repository = environment["GITHUB_REPOSITORY"] {
    return "\(server)/\(repository)"
  }
  var remote = git(["remote", "get-url", "origin"]).trimmingCharacters(in: .whitespacesAndNewlines)
  if remote.hasSuffix(".git") { remote.removeLast(4) }
  if remote.hasPrefix("git@") {
    remote = "https://" + remote.dropFirst(4).replacingOccurrences(of: ":", with: "/")
  }
  return remote.hasPrefix("http") ? remote : nil
}

struct Commit {
  let sha: String
  let subject: String

  var group: String {
    switch subject.split(separator: " ").first?.lowercased() {
    case "add", "added", "introduce": "Added"
    case "fix", "fixed", "repair": "Fixed"
    case "remove", "removed", "drop", "delete": "Removed"
    default: "Changed"
    }
  }
}

func notes(since lastTag: String, version: String) -> String {
  let range = lastTag.isEmpty ? ["HEAD"] : ["\(lastTag)..HEAD"]
  let commits = git(["log", "--format=%H%x00%s", "--no-merges"] + range)
    .split(separator: "\n")
    .compactMap { line -> Commit? in
      let fields = line.split(separator: "\u{0}", maxSplits: 1).map(String.init)
      guard fields.count == 2 else { return nil }
      return Commit(sha: fields[0], subject: fields[1])
    }
  let repository = repositoryURL()
  var lines: [String] = [lastTag.isEmpty ? "## Changes" : "## Changes since \(lastTag)", ""]
  if commits.isEmpty {
    lines.append("No changes.")
    lines.append("")
  }
  for group in ["Added", "Changed", "Fixed", "Removed"] {
    let members = commits.filter { $0.group == group }
    guard !members.isEmpty else { continue }
    lines.append("### \(group)")
    for commit in members {
      let short = String(commit.sha.prefix(7))
      let reference = repository.map { "[\(short)](\($0)/commit/\(commit.sha))" } ?? short
      lines.append("- \(commit.subject) (\(reference))")
    }
    lines.append("")
  }
  if let repository, !lastTag.isEmpty {
    lines.append("**Full changelog:** [\(lastTag)...v\(version)](\(repository)/compare/\(lastTag)...v\(version))")
    lines.append("")
  }
  let footer = ProcessInfo.processInfo.environment["RELEASE_FOOTER"] ?? ".github/release-notes.md"
  if let install = try? String(contentsOfFile: footer, encoding: .utf8) {
    lines.append("---")
    lines.append("")
    lines.append(install.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  return lines.joined(separator: "\n") + "\n"
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "next-version" where arguments.count == 3:
  print(nextVersion(after: arguments[1], bump: arguments[2]))
case "notes" where arguments.count == 3:
  print(notes(since: arguments[1], version: arguments[2]), terminator: "")
default:
  FileHandle.standardError.write(Data("usage: release.swift next-version <last> <patch|minor|major> | notes <last tag> <version>\n".utf8))
  exit(2)
}
