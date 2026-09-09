import GitCore
import SwiftUI

/// Title, a one-line summary, and the sidebar's controls folded into two menus, the way Mail's
/// mailbox header keeps its filter and actions out of the way.
struct SidebarHeader: View {
  @Bindable var model: RepositoryModel
  @Binding var sort: BranchSort

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Branches").font(.headline)
        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 8)
      HStack(spacing: 0) {
        Menu {
          Picker("Sort by", selection: $sort) {
            ForEach(BranchSort.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.inline)
          Divider()
          Toggle("Show all branches", isOn: Binding(get: { model.filter.showAll }, set: { model.setShowAll($0) }))
          Toggle("Show tags", isOn: $model.filter.includeTags)
        } label: {
          Image(systemName: "line.3.horizontal.decrease")
            .frame(width: 26, height: 22)
            .contentShape(Rectangle())
        }
        .help("Sort and filter")
        .accessibilityLabel("Sort and filter")
        Menu {
          Section("Show in graph") {
            Button("None") { model.selectNoBranches() }
            Button("Local branches") { model.selectLocalBranches() }
            Button("Branches with pull requests") { model.selectBranchesWithPullRequests() }
              .disabled(model.branchesWithPullRequests.isEmpty)
          }
          if !model.allRemoteNames.isEmpty {
            Menu("Remotes") {
              ForEach(model.allRemoteNames, id: \.self) { remote in
                Toggle(remote, isOn: Binding(
                  get: { !model.filter.hiddenRemotes.contains(remote) },
                  set: { model.setRemoteHidden(remote, !$0) }
                ))
              }
            }
          }
        } label: {
          Image(systemName: "ellipsis")
            .frame(width: 26, height: 22)
            .contentShape(Rectangle())
        }
        .help("Select branches and remotes")
        .accessibilityLabel("More")
      }
      .menuStyle(.button)
      .buttonStyle(.borderless)
      .menuIndicator(.hidden)
      .padding(.horizontal, 4)
      .glassEffect(.regular.interactive(), in: .capsule)
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .padding(.bottom, 8)
  }

  private var summary: String {
    let branches = model.localBranches + model.remoteNames.flatMap { model.remoteBranches($0) }
    if model.filter.showAll { return "All \(branches.count) branches in graph" }
    return "\(branches.filter(model.filter.isShown).count) of \(branches.count) branches in graph"
  }
}
