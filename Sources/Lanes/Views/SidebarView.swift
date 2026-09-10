import GitCore
import SwiftUI

struct SidebarView: View {
  @Bindable var model: RepositoryModel
  @State private var query = ""
  @AppStorage("branchSort") private var sort = BranchSort.name
  @AppStorage("sidebar.collapsed") private var collapsed = ""

  var body: some View {
    VStack(spacing: 0) {
      SidebarHeader(model: model, sort: $sort)
      List {
        Section(isExpanded: expansion(for: "branches")) {
          ForEach(filtered(model.sortedLocalBranches(by: sort))) { ref in
            BranchRow(model: model, ref: ref, sort: sort)
          }
        } header: {
          Text("Branches")
        }
        ForEach(model.remoteNames, id: \.self) { remote in
          Section(isExpanded: expansion(for: "remote:" + remote)) {
            ForEach(filtered(model.sortedRemoteBranches(remote, by: sort))) { ref in
              BranchRow(model: model, ref: ref, sort: sort)
            }
          } header: {
            Text(remote)
          }
        }
        Section(isExpanded: expansion(for: "tags")) {
          ForEach(filtered(model.sortedTags(by: sort))) { ref in
            TagRow(model: model, ref: ref, sort: sort)
          }
        } header: {
          Text("Tags")
        }
        Section(isExpanded: expansion(for: "stashes")) {
          ForEach(model.stashes.filter { matches($0.title) || matches($0.branch ?? "") }) { stash in
            StashRow(model: model, stash: stash)
          }
        } header: {
          Text("Stashes")
        }
      }
      .listStyle(.sidebar)
    }
    .searchable(text: $query, placement: .sidebar, prompt: "Filter")
  }

  private func matches(_ text: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespaces)
    return needle.isEmpty || text.localizedCaseInsensitiveContains(needle)
  }

  private func filtered(_ refs: [Ref]) -> [Ref] {
    refs.filter { matches($0.shortName) }
  }

  private var collapsedSections: Set<String> {
    Set(collapsed.split(separator: ",").map(String.init))
  }

  /// Sections stay collapsed across launches; ids are "branches", "remote:<name>", "tags", "stashes".
  private func expansion(for id: String) -> Binding<Bool> {
    Binding(
      get: { !collapsedSections.contains(id) },
      set: { expanded in
        var ids = collapsedSections
        if expanded { ids.remove(id) } else { ids.insert(id) }
        collapsed = ids.sorted().joined(separator: ",")
      }
    )
  }
}

private struct BranchRow: View {
  let model: RepositoryModel
  let ref: Ref
  let sort: BranchSort

  var body: some View {
    HStack(spacing: 6) {
      Checkbox(isOn: shown, label: ref.shortName)
        .disabled(ref.isHead)
        .help(ref.isHead ? "The checked-out branch is always shown" : "Show in the graph")
      Text(ref.branchName)
        .lineLimit(1)
        .truncationMode(.middle)
        .fontWeight(ref.isHead ? .semibold : .regular)
      if let pullRequest = model.pullRequest(for: ref) {
        PullRequestBadge(pullRequest: pullRequest)
      }
      Spacer(minLength: 0)
      if let date = sortDate {
        Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .help(sort == .forkDate ? "Forked from the trunk" : "Last commit")
      }
      if model.trunkRef?.fullName == ref.fullName {
        Image(systemName: "arrow.triangle.merge").foregroundStyle(.secondary).imageScale(.small).help("Trunk")
      }
      if ref.isHead {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).imageScale(.small)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { revealInHistory() }
    .contextMenu { BranchMenuItems(model: model, ref: ref) }
  }

  private var sortDate: Date? {
    switch sort {
    case .forkDate: model.forkDates[ref.fullName]
    case .lastCommit: ref.committerDate
    case .name, .pullRequest: nil
    }
  }

  private var shown: Binding<Bool> {
    Binding(
      get: { model.filter.isShown(ref) },
      set: { model.filter.setShown(ref, $0, allRefs: model.refs) }
    )
  }

  private func revealInHistory() {
    if model.isTrunkViewActive, let group = model.trunkLayout?.groups.first(where: { $0.names.contains(ref.shortName) }) {
      model.selection = .branch(group.id)
      return
    }
    guard model.commits.contains(where: { $0.sha == ref.target }) else { return }
    model.selection = .commit(ref.target)
  }
}

private struct TagRow: View {
  let model: RepositoryModel
  let ref: Ref
  let sort: BranchSort

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "tag").foregroundStyle(.secondary).imageScale(.small)
      Text(ref.shortName).lineLimit(1).truncationMode(.middle)
      Spacer(minLength: 0)
      if sort == .lastCommit, let date = ref.committerDate {
        Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      if model.commits.contains(where: { $0.sha == ref.target }) { model.selection = .commit(ref.target) }
    }
    .contextMenu { RefMenuItems(model: model, names: [ref.shortName]) }
  }
}

private struct StashRow: View {
  let model: RepositoryModel
  let stash: Stash

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: "archivebox").foregroundStyle(.secondary).imageScale(.small).padding(.top, 2)
      VStack(alignment: .leading, spacing: 1) {
        Text(stash.title).lineLimit(1).truncationMode(.tail)
        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      model.mode = .history
      model.selection = .stash(stash.commit.sha)
    }
    .contextMenu {
      Button("Apply") { model.applyStash(stash) }
      Button("Pop") { model.popStash(stash) }
      Divider()
      Button("Drop…", role: .destructive) { model.stashToDrop = stash }
    }
  }

  private var detail: String {
    let when = stash.commit.committerDate.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    return stash.branch.map { "on \($0), \(when)" } ?? when
  }
}
