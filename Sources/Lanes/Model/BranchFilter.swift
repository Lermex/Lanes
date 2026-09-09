import Foundation
import GitCore

struct BranchFilter: Codable, Equatable, Sendable {
  var showAll: Bool
  var selected: Set<String>
  var includeTags: Bool
  var hiddenRemotes: Set<String>

  static let initial = BranchFilter(showAll: true, selected: [], includeTags: false, hiddenRemotes: [])

  init(showAll: Bool, selected: Set<String>, includeTags: Bool, hiddenRemotes: Set<String>) {
    self.showAll = showAll
    self.selected = selected
    self.includeTags = includeTags
    self.hiddenRemotes = hiddenRemotes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    showAll = try container.decode(Bool.self, forKey: .showAll)
    selected = try container.decode(Set<String>.self, forKey: .selected)
    includeTags = try container.decode(Bool.self, forKey: .includeTags)
    hiddenRemotes = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenRemotes) ?? []
  }

  func isRemoteHidden(_ ref: Ref) -> Bool {
    ref.remote.map(hiddenRemotes.contains) ?? false
  }

  func isShown(_ ref: Ref) -> Bool {
    !isRemoteHidden(ref) && (showAll || selected.contains(ref.fullName) || ref.isHead)
  }

  func revisions(refs: [Ref]) -> [String] {
    let tags = includeTags ? ["--tags"] : []
    if showAll {
      let remotes = Set(refs.compactMap(\.remote)).subtracting(hiddenRemotes).sorted()
      return ["HEAD", "--branches"] + remotes.map { "--remotes=\($0)" } + tags
    }
    let visible = refs.filter { !isRemoteHidden($0) }.map(\.fullName)
    let chosen = selected.intersection(visible).sorted()
    return ["HEAD"] + chosen + tags
  }

  mutating func setShown(_ ref: Ref, _ shown: Bool, allRefs: [Ref]) {
    if showAll {
      showAll = false
      selected = Set(allRefs.filter { $0.kind != .tag }.map(\.fullName))
    }
    if shown {
      selected.insert(ref.fullName)
    } else {
      selected.remove(ref.fullName)
    }
  }
}

enum BranchFilterStore {
  private static var defaults: UserDefaults { .standard }

  private static func key(for repository: RepositoryInfo) -> String {
    "branchFilter:" + repository.commonGitDir.standardizedFileURL.path
  }

  static func load(for repository: RepositoryInfo) -> BranchFilter {
    guard let data = defaults.data(forKey: key(for: repository)),
      let filter = try? JSONDecoder().decode(BranchFilter.self, from: data)
    else { return .initial }
    return filter
  }

  static func save(_ filter: BranchFilter, for repository: RepositoryInfo) {
    guard let data = try? JSONEncoder().encode(filter) else { return }
    defaults.set(data, forKey: key(for: repository))
  }
}

enum RecentRepositories {
  private static let key = "recentRepositories"
  private static let limit = 12

  static func load() -> [URL] {
    (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  static func remember(_ url: URL) {
    let path = url.standardizedFileURL.path
    let others = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != path }
    UserDefaults.standard.set(Array(([path] + others).prefix(limit)), forKey: key)
  }

  static func forget(_ url: URL) {
    let path = url.standardizedFileURL.path
    let others = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != path }
    UserDefaults.standard.set(others, forKey: key)
  }
}

struct TrunkViewSettings: Codable, Equatable, Sendable {
  var enabled: Bool
  var trunk: String?
  var expanded: Set<String>

  static let initial = TrunkViewSettings(enabled: false, trunk: nil, expanded: [])
}

enum TrunkViewStore {
  private static func key(for repository: RepositoryInfo) -> String {
    "trunkView:" + repository.commonGitDir.standardizedFileURL.path
  }

  static func load(for repository: RepositoryInfo) -> TrunkViewSettings {
    guard let data = UserDefaults.standard.data(forKey: key(for: repository)),
      let settings = try? JSONDecoder().decode(TrunkViewSettings.self, from: data)
    else { return .initial }
    return settings
  }

  static func save(_ settings: TrunkViewSettings, for repository: RepositoryInfo) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    UserDefaults.standard.set(data, forKey: key(for: repository))
  }
}
