import GitCore
import SwiftUI

struct SidebarView: View {
  @Bindable var model: RepositoryModel
  @State private var query = ""
  @State private var collapsedRemotes: Set<String> = []
  @AppStorage("branchSort") private var sort = BranchSort.name

  var body: some View {
    VStack(spacing: 0) {
      SidebarHeader(model: model, sort: $sort)
      List {
        Section("Branches") {
          ForEach(filtered(model.sortedLocalBranches(by: sort))) { ref in
            BranchRow(model: model, ref: ref, sort: sort)
          }
        }
        ForEach(model.remoteNames, id: \.self) { remote in
          Section(isExpanded: expansion(for: remote)) {
            ForEach(filtered(model.sortedRemoteBranches(remote, by: sort))) { ref in
              BranchRow(model: model, ref: ref, sort: sort)
            }
          } header: {
            Text(remote)
          }
        }
      }
      .listStyle(.sidebar)
    }
    .searchable(text: $query, placement: .sidebar, prompt: "Filter branches")
  }

  private func filtered(_ refs: [Ref]) -> [Ref] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    guard !needle.isEmpty else { return refs }
    return refs.filter { $0.shortName.localizedCaseInsensitiveContains(needle) }
  }

  private func expansion(for remote: String) -> Binding<Bool> {
    Binding(
      get: { !collapsedRemotes.contains(remote) },
      set: { expanded in
        if expanded { collapsedRemotes.remove(remote) } else { collapsedRemotes.insert(remote) }
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
