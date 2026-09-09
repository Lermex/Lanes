import GitCore
import SwiftUI

struct SidebarView: View {
  @Bindable var model: RepositoryModel
  @State private var query = ""
  @State private var collapsedRemotes: Set<String> = []

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
      }
      Section("Branches") {
        ForEach(filtered(model.localBranches)) { ref in
          BranchRow(model: model, ref: ref)
        }
      }
      ForEach(model.remoteNames, id: \.self) { remote in
        Section(isExpanded: expansion(for: remote)) {
          ForEach(filtered(model.remoteBranches(remote))) { ref in
            BranchRow(model: model, ref: ref)
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
  }

  private var remotesLabel: String {
    let hidden = model.hiddenRemoteNames.count
    return hidden == 0 ? "Remotes" : "Remotes (\(hidden) hidden)"
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

  var body: some View {
    HStack(spacing: 6) {
      Toggle(isOn: shown) { EmptyView() }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel(ref.shortName)
        .disabled(ref.isHead)
        .help(ref.isHead ? "The checked-out branch is always shown" : "Show in the graph")
      Text(displayName)
        .lineLimit(1)
        .truncationMode(.middle)
        .fontWeight(ref.isHead ? .semibold : .regular)
      if let pullRequest = model.pullRequest(for: ref) {
        PullRequestBadge(pullRequest: pullRequest)
      }
      Spacer(minLength: 0)
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
      Button("Use as Trunk") { model.setTrunk(ref) }
        .disabled(model.trunkRef?.fullName == ref.fullName)
    }
  }

  private var displayName: String {
    guard let remote = ref.remote, ref.shortName.hasPrefix(remote + "/") else { return ref.shortName }
    return String(ref.shortName.dropFirst(remote.count + 1))
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
