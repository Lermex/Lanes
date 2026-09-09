import Foundation

public struct PullRequest: Sendable, Hashable, Identifiable, Decodable {
  public let number: Int
  public let title: String
  public let url: URL
  public let headRefName: String
  public let isDraft: Bool
  public let author: Author?

  public struct Author: Sendable, Hashable, Decodable {
    public let login: String
  }

  public var id: Int { number }
}

public enum GitHubCLI {
  public static func locate() -> URL? {
    ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
      .first { FileManager.default.isExecutableFile(atPath: $0) }
      .map { URL(fileURLWithPath: $0) }
  }

  public static func openPullRequests(workTree: URL) async throws -> [PullRequest] {
    guard let gh = locate() else { throw GitError(arguments: ["gh"], exitCode: 127, stderr: "gh not installed") }
    let output = try await Subprocess.run(
      gh,
      arguments: ["pr", "list", "--state", "open", "--limit", "300", "--json", "number,title,url,headRefName,isDraft,author"],
      workingDirectory: workTree,
      environment: ["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "GIT_TERMINAL_PROMPT": "0"]
    )
    guard output.exitCode == 0 else {
      throw GitError(arguments: ["gh", "pr", "list"], exitCode: output.exitCode, stderr: output.stderr)
    }
    return try JSONDecoder().decode([PullRequest].self, from: output.stdout)
  }
}
