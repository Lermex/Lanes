import GitCore
import SwiftUI

struct SidebarView: View {
  @Bindable var model: RepositoryModel
  @State private var query = ""
  @AppStorage("branchSort") private var sort = BranchSort.name
  @AppStorage("sidebar.collapsed") private var collapsed = ""

  var body: some View {
    List {
      Section(isExpanded: expansion(for: "branches")) {
        ForEach(filtered(model.sortedLocalBranches(by: sort))) { ref in
          BranchRow(model: model, ref: ref, sort: sort)
        }
        ForEach(model.remoteNames, id: \.self) { remote in
          Text(remote)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
          ForEach(filtered(model.sortedRemoteBranches(remote, by: sort))) { ref in
            BranchRow(model: model, ref: ref, sort: sort)
          }
        }
      } header: {
        SidebarGroupHeader(title: "Branches", summary: branchSummary) {
          SidebarBranchControls(model: model, sort: $sort)
        }
      }
      Section(isExpanded: expansion(for: "tags")) {
        ForEach(filtered(model.sortedTags(by: sort))) { ref in
          TagRow(model: model, ref: ref, sort: sort)
        }
      } header: {
        SidebarGroupHeader(title: "Tags", summary: count(model.tags.count, "tag")) { EmptyView() }
      }
      Section(isExpanded: expansion(for: "stashes")) {
        ForEach(model.stashes.filter { matches($0.title) || matches($0.branch ?? "") }) { stash in
          StashRow(model: model, stash: stash)
        }
      } header: {
        SidebarGroupHeader(title: "Stashes", summary: count(model.stashes.count, "stash", plural: "stashes")) { EmptyView() }
      }
    }
    .listStyle(.sidebar)
    .searchable(text: $query, placement: .sidebar, prompt: "Filter")
  }

  private var branchSummary: String {
    let branches = model.localBranches + model.remoteNames.flatMap { model.remoteBranches($0) }
    if model.filter.showAll { return "All \(branches.count) in graph" }
    return "\(branches.filter(model.filter.isShown).count) of \(branches.count) in graph"
  }

  private func count(_ number: Int, _ noun: String, plural: String? = nil) -> String {
    number == 0 ? "None" : "\(number) \(number == 1 ? noun : (plural ?? noun + "s"))"
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

  /// Groups stay collapsed across launches; ids are "branches", "tags" and "stashes".
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
    .onTapGesture { model.reveal(ref) }
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
    .onTapGesture { model.reveal(ref) }
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
    .listRowBackground(
      isSelected ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.28)).padding(.horizontal, 4) : nil
    )
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

  private var isSelected: Bool { model.selection == .stash(stash.commit.sha) }

  private var detail: String {
    let when = stash.commit.committerDate.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    return stash.branch.map { "on \($0), \(when)" } ?? when
  }
}
