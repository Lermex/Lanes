import GitCore
import SwiftUI

struct DetailView: View {
  @Bindable var model: RepositoryModel

  var body: some View {
    switch model.selection {
    case .workingCopy:
      WorkingCopyView(model: model)
    case .commit(let sha):
      if let commit = model.commits.first(where: { $0.sha == sha }) {
        CommitDetailView(model: model, commit: commit)
      } else {
        placeholder("Commit not loaded")
      }
    case .branch(let id):
      if let group = model.trunkLayout?.group(id: id) {
        BranchGroupDetailView(model: model, group: group)
      } else {
        placeholder("Branch not in view")
      }
    case nil:
      placeholder("Select a commit")
    }
  }

  private func placeholder(_ text: String) -> some View {
    Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct BranchGroupDetailView: View {
  let model: RepositoryModel
  let group: BranchGroup

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        ForEach(group.names, id: \.self) { name in
          RefChip(name: name, kind: group.isMerged ? nil : model.refKinds[name], isHead: false)
        }
        if let pullRequest = group.names.lazy.compactMap({ model.pullRequest(forBranchName: $0) }).first {
          PullRequestBadge(pullRequest: pullRequest)
          Text(pullRequest.title).lineLimit(1).foregroundStyle(.secondary)
        }
        Spacer()
        Text(summary).foregroundStyle(.secondary)
      }
      .padding(10)
      Divider()
      List(group.commits) { commit in
        HStack(spacing: 8) {
          Text(commit.shortSha).font(.body.monospaced()).foregroundStyle(.secondary)
          Text(commit.subject).lineLimit(1)
          Spacer()
          Text(commit.authorName).foregroundStyle(.secondary).lineLimit(1)
          Text(commit.authorDate, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
            .foregroundStyle(.secondary).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selection = .commit(commit.sha) }
      }
      .listStyle(.plain)
    }
  }

  private var summary: String {
    let count = "\(group.commits.count) commit\(group.commits.count == 1 ? "" : "s")"
    if group.isMerged { return "\(count), merged into trunk" }
    guard let fork = group.forkSha, let behind = group.behind else { return "\(count), fork point outside loaded history" }
    return "\(count) ahead, \(behind) behind, forked at \(fork.prefix(8))"
  }
}
