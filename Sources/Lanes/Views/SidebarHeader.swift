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
          Toggle("Show all branches", isOn: Binding(get: { model.filter.showAll }, set: { model.setShowAll($0) }))
          Toggle("Show tags", isOn: $model.filter.includeTags)
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
          Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isFiltering ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(width: 38, height: 30)
            .contentShape(Rectangle())
        }
        .help("Filter what the sidebar and graph show")
        .accessibilityLabel("Filter")
        Menu {
          Picker("Sort by", selection: $sort) {
            ForEach(BranchSort.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.inline)
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .medium))
            .frame(width: 38, height: 30)
            .contentShape(Rectangle())
        }
        .help("Sort")
        .accessibilityLabel("More")
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .padding(.horizontal, 4)
      .glassEffect(.regular.interactive(), in: Capsule())
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .padding(.bottom, 8)
  }

  /// Mirrors Mail, whose filter button is tinted while a filter is on.
  private var isFiltering: Bool {
    !model.filter.showAll || !model.filter.hiddenRemotes.isEmpty
  }

  private var summary: String {
    let branches = model.localBranches + model.remoteNames.flatMap { model.remoteBranches($0) }
    if model.filter.showAll { return "All \(branches.count) branches in graph" }
    return "\(branches.filter(model.filter.isShown).count) of \(branches.count) branches in graph"
  }
}
