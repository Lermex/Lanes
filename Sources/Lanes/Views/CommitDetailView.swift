import GitCore
import SwiftUI

struct CommitDetailView: View {
  @Bindable var model: RepositoryModel
  let commit: Commit

  var body: some View {
    SplitPanes(.horizontal, storageKey: "split.commitDetail", firstMinimum: 260, secondMinimum: 360, defaultFraction: 0.4) {
      VStack(alignment: .leading, spacing: 0) {
        header
        Divider()
        if let files = model.commitDiffs[commit.sha] {
          List(selection: $model.selectedCommitPath) {
            ForEach(files) { file in
              HStack(spacing: 8) {
                StatusIcon(kind: kind(of: file))
                Flexible { Text(file.path).lineLimit(1).truncationMode(.middle) }
              }
              .frame(height: 24)
              .tag(file.path)
              .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6))
              .listRowSeparator(.hidden)
            }
          }
          .listStyle(.plain)
          .environment(\.defaultMinListRowHeight, 24)
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .task(id: commit.sha) { await model.ensureCommitDiff(sha: commit.sha) }
    } second: {
      if let path = model.selectedCommitPath, let file = model.diff(forCommit: commit.sha, path: path) {
        VStack(spacing: 0) {
          HStack {
            Text(file.isRename ? "\(file.oldPath ?? "") → \(file.path)" : file.path)
              .font(.body.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          Divider()
          DiffView(model: model, source: .commitFile(sha: commit.sha, path: path), file: file, hunkAction: nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Select a file").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(commit.subject).font(.headline).textSelection(.enabled)
      if !commit.body.isEmpty {
        Text(commit.body).font(.callout).textSelection(.enabled).lineLimit(8)
      }
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
        GridRow {
          Text("Commit").foregroundStyle(.secondary)
          Text(commit.sha).font(.callout.monospaced()).textSelection(.enabled)
        }
        GridRow {
          Text("Parents").foregroundStyle(.secondary)
          HStack {
            ForEach(commit.parents, id: \.self) { parent in
              Button(String(parent.prefix(8))) { model.selection = .commit(parent) }
                .buttonStyle(.link)
                .font(.callout.monospaced())
            }
          }
        }
        GridRow {
          Text("Author").foregroundStyle(.secondary)
          Text("\(commit.authorName) <\(commit.authorEmail)>").textSelection(.enabled)
        }
        GridRow {
          Text("Date").foregroundStyle(.secondary)
          Text(commit.authorDate, format: .dateTime)
        }
      }
      .font(.callout)
      if !commit.decorations.isEmpty {
        HStack {
          ForEach(commit.decorations, id: \.self) { decoration in
            RefChip(name: decoration, kind: model.refKinds[decoration], isHead: decoration == "HEAD")
          }
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func kind(of file: FileDiff) -> ChangeKind {
    if file.isNewFile { return .added }
    if file.isDeletedFile { return .deleted }
    if file.isRename { return .renamed }
    return .modified
  }
}
