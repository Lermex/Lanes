import Foundation
import Synchronization

public struct GitError: Error, Sendable, CustomStringConvertible {
  public let arguments: [String]
  public let exitCode: Int32
  public let stderr: String

  public var description: String {
    let command = (["git"] + arguments).joined(separator: " ")
    return stderr.isEmpty ? "\(command) exited with \(exitCode)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct GitOutput: Sendable {
  public let stdout: Data
  public let stderr: String
  public let exitCode: Int32

  public var text: String { String(decoding: stdout, as: UTF8.self) }
}

public final class Git: Sendable {
  public let executable: URL
  public let workingDirectory: URL

  public init(workingDirectory: URL, executable: URL = Git.locateExecutable()) {
    self.workingDirectory = workingDirectory
    self.executable = executable
  }

  public static func locateExecutable() -> URL {
    let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
    let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    return URL(fileURLWithPath: found)
  }

  @discardableResult
  public func run(_ arguments: [String], stdin: Data? = nil, allowedExitCodes: Set<Int32> = [0]) async throws -> GitOutput {
    let output = try await execute(arguments, stdin: stdin)
    guard allowedExitCodes.contains(output.exitCode) else {
      throw GitError(arguments: arguments, exitCode: output.exitCode, stderr: output.stderr)
    }
    return output
  }

  public func text(_ arguments: [String], allowedExitCodes: Set<Int32> = [0]) async throws -> String {
    try await run(arguments, allowedExitCodes: allowedExitCodes).text
  }

  private func execute(_ arguments: [String], stdin: Data?) async throws -> GitOutput {
    try await Subprocess.run(
      executable, arguments: arguments, workingDirectory: workingDirectory, stdin: stdin,
      environment: await Self.subprocessEnvironment()
    )
  }

  /// git and ssh run without a terminal here, so their questions go to the bundled askpass
  /// dialog, and the agent socket comes from launchd when the app was started without one.
  public static func subprocessEnvironment() async -> [String: String] {
    environment(
      base: ProcessInfo.processInfo.environment,
      askpass: Bundle.main.url(forResource: "askpass", withExtension: "sh"),
      agentSocket: await launchdAgentSocket()
    )
  }

  static func environment(base: [String: String], askpass: URL?, agentSocket: String?) -> [String: String] {
    var environment = base
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    environment["LC_ALL"] = "en_US.UTF-8"
    environment["GIT_TERMINAL_PROMPT"] = "0"
    if let askpass {
      environment["GIT_ASKPASS"] = askpass.path
      environment["SSH_ASKPASS"] = askpass.path
      environment["SSH_ASKPASS_REQUIRE"] = "force"
    }
    if environment["SSH_AUTH_SOCK"] == nil, let agentSocket {
      environment["SSH_AUTH_SOCK"] = agentSocket
    }
    return environment
  }

  private static let agentSocketLookup = Mutex<String??>(nil)

  private static func launchdAgentSocket() async -> String? {
    if ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] != nil { return nil }
    if let cached = agentSocketLookup.withLock({ $0 }) { return cached }
    let output = try? await Subprocess.run(
      URL(fileURLWithPath: "/bin/launchctl"), arguments: ["getenv", "SSH_AUTH_SOCK"], workingDirectory: URL(fileURLWithPath: "/")
    )
    let socket = output?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let result = socket.flatMap { $0.isEmpty ? nil : $0 }
    agentSocketLookup.withLock { $0 = .some(result) }
    return result
  }
}

public enum Subprocess {
  public static func run(
    _ executable: URL, arguments: [String], workingDirectory: URL, stdin: Data? = nil, environment: [String: String] = [:]
  ) async throws -> GitOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: { _, override in override })
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdinPipe = stdin.map { _ in Pipe() }
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = stdinPipe ?? FileHandle.nullDevice

    try process.run()
    if let stdin, let stdinPipe {
      let handle = stdinPipe.fileHandleForWriting
      try handle.write(contentsOf: stdin)
      try handle.close()
    }
    async let stdoutData = readToEnd(stdoutPipe.fileHandleForReading)
    async let stderrData = readToEnd(stderrPipe.fileHandleForReading)
    let exitCode = await waitForExit(process)
    return GitOutput(
      stdout: await stdoutData,
      stderr: String(decoding: await stderrData, as: UTF8.self),
      exitCode: exitCode
    )
  }

  private static func readToEnd(_ handle: FileHandle) async -> Data {
    await Task.detached { handle.readDataToEndOfFile() }.value
  }

  // the termination handler can fire even after the isRunning check below, so resume exactly once
  private static func waitForExit(_ process: Process) async -> Int32 {
    await withCheckedContinuation { continuation in
      let resumed = Mutex(false)
      let resumeOnce: @Sendable (Int32) -> Void = { status in
        let first = resumed.withLock { flag in
          defer { flag = true }
          return !flag
        }
        if first { continuation.resume(returning: status) }
      }
      process.terminationHandler = { resumeOnce($0.terminationStatus) }
      if !process.isRunning { resumeOnce(process.terminationStatus) }
    }
  }
}
