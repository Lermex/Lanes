import GitCore
import SwiftUI

struct SidebarView: View {
  @Bindable var model: RepositoryModel
  @State private var query = ""
  @State private var collapsedRemotes: Set<String> = []
  @AppStorage("branchSort") private var sort = BranchSort.name
  @State private var renaming: Ref?
  @State private var newBranchName = ""
  @State private var deleting: Ref?
  @State private var forceDeleting: Ref?

  var body: some View {
    List {
      Section {
        Toggle("Show all branches", isOn: Binding(get: { model.filter.showAll }, set: { model.setShowAll($0) }))
        Toggle("Show tags", isOn: $model.filter.includeTags)
        if !model.allRemoteNames.isEmpty {
          Menu {
            ForEach(model.allRemoteNames, id: \.self) { remote in
              Toggle(remote, isOn: Binding(
                get: { !model.filter.hiddenRemotes.contains(remote) },
                set: { model.setRemoteHidden(remote, !$0) }
              ))
            }
          } label: {
            Label(remotesLabel, systemImage: "network")
          }
          .accessibilityLabel("Remotes")
        }
        HStack(spacing: 10) {
          Text("Select").foregroundStyle(.secondary)
          Button("None") { model.selectNoBranches() }
          Button("Local") { model.selectLocalBranches() }
          Button("With PRs") { model.selectBranchesWithPullRequests() }
            .disabled(model.branchesWithPullRequests.isEmpty)
            .help("Turn on every branch that has an open pull request")
        }
        .controlSize(.small)
        .buttonStyle(.link)
        HStack(spacing: 6) {
          Text("Sort by").foregroundStyle(.secondary)
          Picker("Sort branches by", selection: $sort) {
            ForEach(BranchSort.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
        }
        .controlSize(.small)
      }
      Section("Branches") {
        ForEach(branches(model.localBranches)) { ref in
          BranchRow(model: model, ref: ref, sort: sort, menuAction: handle)
        }
      }
      ForEach(model.remoteNames, id: \.self) { remote in
        Section(isExpanded: expansion(for: remote)) {
          ForEach(branches(model.remoteBranches(remote))) { ref in
            BranchRow(model: model, ref: ref, sort: sort, menuAction: handle)
          }
        } header: {
          Text(remote)
        }
      }
      if !model.hiddenRemoteNames.isEmpty {
        Section("Hidden remotes") {
          ForEach(model.hiddenRemoteNames, id: \.self) { remote in
            HStack {
              Image(systemName: "eye.slash").foregroundStyle(.secondary)
              Text(remote).foregroundStyle(.secondary)
              Spacer()
              Button("Show") { model.setRemoteHidden(remote, false) }
                .buttonStyle(.link)
                .controlSize(.small)
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .searchable(text: $query, placement: .sidebar, prompt: "Filter branches")
    .alert("Rename Branch", isPresented: presenting($renaming)) {
      TextField("New name", text: $newBranchName)
      Button("Rename") {
        if let ref = renaming { model.rename(ref, to: newBranchName) }
      }
      .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Rename “\(renaming?.shortName ?? "")”.")
    }
    .confirmationDialog(
      "Delete “\(deleting?.shortName ?? "")”?", isPresented: presenting($deleting), titleVisibility: .visible
    ) {
      Button(deleting?.kind == .remoteBranch ? "Delete on Remote" : "Delete", role: .destructive) {
        guard let ref = deleting else { return }
        Task { if await !model.deleteBranch(ref, force: false) { forceDeleting = ref } }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      if let remote = deleting?.remote {
        Text("The branch is removed from \(remote).")
      } else {
        Text("The local branch is removed. Git refuses if it has unmerged commits; you can force it then.")
      }
    }
    .confirmationDialog(
      "“\(forceDeleting?.shortName ?? "")” is not fully merged", isPresented: presenting($forceDeleting),
      titleVisibility: .visible
    ) {
      Button("Delete Anyway", role: .destructive) {
        guard let ref = forceDeleting else { return }
        Task { _ = await model.deleteBranch(ref, force: true) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Its commits are not reachable from its upstream or HEAD; deleting it may lose them.")
    }
  }

  private func handle(_ action: BranchMenuAction, _ ref: Ref) {
    switch action {
    case .rename:
      newBranchName = ref.shortName
      renaming = ref
    case .delete:
      deleting = ref
    }
  }

  private func presenting(_ value: Binding<Ref?>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
  }

  private var remotesLabel: String {
    let hidden = model.hiddenRemoteNames.count
    return hidden == 0 ? "Remotes" : "Remotes (\(hidden) hidden)"
  }

  private func branches(_ refs: [Ref]) -> [Ref] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    let matching = needle.isEmpty ? refs : refs.filter { $0.shortName.localizedCaseInsensitiveContains(needle) }
    return model.sortedBranches(matching, by: sort)
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

enum BranchMenuAction {
  case rename
  case delete
}

private struct BranchRow: View {
  let model: RepositoryModel
  let ref: Ref
  let sort: BranchSort
  let menuAction: (BranchMenuAction, Ref) -> Void

  var body: some View {
    HStack(spacing: 6) {
      Toggle(isOn: shown) { EmptyView() }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel(ref.shortName)
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
    .contextMenu {
      Button("Switch to \(ref.branchName)") { model.switchTo(ref) }
        .disabled(ref.isHead)
      if ref.kind == .localBranch {
        let remotes = model.pushRemotes(for: ref)
        if remotes.count == 1, let remote = remotes.first {
          Button("Push to \(remote)") { model.push(ref, to: remote) }
        } else if remotes.count > 1 {
          Menu("Push to") {
            ForEach(remotes, id: \.self) { remote in
              Button(remote) { model.push(ref, to: remote) }
            }
          }
        }
        Button("Rename…") { menuAction(.rename, ref) }
      }
      Button(ref.remote.map { "Delete from \($0)…" } ?? "Delete…", role: .destructive) { menuAction(.delete, ref) }
        .disabled(ref.isHead)
      Divider()
      Button("Use as Trunk") { model.setTrunk(ref) }
        .disabled(model.trunkRef?.fullName == ref.fullName)
    }
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
