import Foundation

public struct RepositoryInfo: Sendable, Equatable {
  public let workTree: URL
  public let gitDir: URL
  public let commonGitDir: URL

  public var displayName: String { workTree.lastPathComponent }
}

public enum RepositoryDiscovery {
  public static func discover(at url: URL, git executable: URL = Git.locateExecutable()) async throws -> RepositoryInfo {
    let git = Git(workingDirectory: url, executable: executable)
    let output = try await git.text(["rev-parse", "--show-toplevel", "--absolute-git-dir", "--git-common-dir"])
    let lines = output.split(separator: "\n").map(String.init)
    guard lines.count == 3 else { throw GitError(arguments: ["rev-parse"], exitCode: 0, stderr: "unexpected rev-parse output") }
    let workTree = URL(fileURLWithPath: lines[0], isDirectory: true)
    let gitDir = URL(fileURLWithPath: lines[1], isDirectory: true)
    let commonGitDir = URL(fileURLWithPath: lines[2], isDirectory: true, relativeTo: workTree).standardizedFileURL
    return RepositoryInfo(workTree: workTree, gitDir: gitDir, commonGitDir: commonGitDir)
  }
}
