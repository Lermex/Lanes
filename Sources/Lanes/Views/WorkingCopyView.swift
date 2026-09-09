import AppKit
import GitCore
import SwiftUI

struct WorkingCopyView: View {
  @Bindable var model: RepositoryModel

  var body: some View {
    HSplitView {
      VStack(spacing: 0) {
        PendingFilesList(model: model)
        Divider()
        CommitComposer(model: model)
      }
      .frame(minWidth: 340, idealWidth: 640, maxWidth: .infinity)
      diffPane
        .frame(minWidth: 400, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder
  private var diffPane: some View {
    if let change = model.selectedChange {
      ChangeDiffPane(model: model, change: change)
    } else if model.selectedChanges.count > 1 {
      MultiSelectionPane(model: model, changes: model.selectedChanges)
    } else {
      Text("No file selected").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct PendingFilesList: View {
  @Bindable var model: RepositoryModel
  @AppStorage("pendingFilesSort") private var sort = PendingSort.path

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Pending files, sorted by", selection: $sort) {
          ForEach(PendingSort.allCases) { Text($0.label).tag($0) }
        }
        .controlSize(.small)
        .fixedSize()
        Spacer()
        Text("\(model.status.changeCount) files").font(.caption).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      Divider()
      List(selection: $model.selectedChangeIDs) {
        section(title: "Staged files", changes: sorted(model.status.staged), isStaged: true)
        section(title: "Unstaged files", changes: sorted(model.status.unstaged), isStaged: false)
      }
      .listStyle(.plain)
      .environment(\.defaultMinListRowHeight, 24)
      .onKeyPress(.space) {
        model.toggleStagedSelection()
        return .handled
      }
    }
  }

  private func section(title: String, changes: [WorkingCopyChange], isStaged: Bool) -> some View {
    Section {
      ForEach(changes) { change in
        PendingFileRow(model: model, change: change)
          .tag(change.id)
          .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6))
          .listRowSeparator(.hidden)
      }
    } header: {
      HStack(spacing: 8) {
        Toggle(isOn: Binding(get: { isStaged && !changes.isEmpty }, set: { checked in
          if checked { model.stage(changes) } else { model.unstage(changes) }
        })) { EmptyView() }
          .toggleStyle(.checkbox)
          .labelsHidden()
          .disabled(changes.isEmpty)
          .accessibilityLabel(isStaged ? "Unstage all files" : "Stage all files")
        Text(title).font(.headline)
        Text("\(changes.count)").foregroundStyle(.secondary).monospacedDigit()
        Spacer()
      }
      .padding(.vertical, 2)
    }
  }

  private func sorted(_ changes: [WorkingCopyChange]) -> [WorkingCopyChange] {
    switch sort {
    case .path: changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    case .status: changes.sorted { ($0.kind.symbol, $0.path) < ($1.kind.symbol, $1.path) }
    case .fileName: changes.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }
  }
}

enum PendingSort: String, CaseIterable, Identifiable {
  case path, fileName, status

  var id: String { rawValue }
  var label: String {
    switch self {
    case .path: "path"
    case .fileName: "file name"
    case .status: "status"
    }
  }
}

private struct PendingFileRow: View {
  let model: RepositoryModel
  let change: WorkingCopyChange

  var body: some View {
    HStack(spacing: 8) {
      Toggle(isOn: Binding(get: { change.area == .staged }, set: { _ in model.toggleStaged([change]) })) { EmptyView() }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(change.kind == .unmerged)
        .accessibilityLabel((change.area == .staged ? "Unstage " : "Stage ") + change.path)
      StatusIcon(kind: change.kind)
      Text(change.path)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 4)
      Menu {
        if change.area == .staged {
          Button("Unstage") { model.unstage(change) }
        } else {
          Button("Stage") { model.stage(change) }
        }
        Divider()
        Button("Copy Path") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(change.path, forType: .string)
        }
        Button("Reveal in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([model.info.workTree.appending(path: change.path)])
        }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Actions for \(change.path)")
    }
    .frame(height: 24)
  }
}

struct StatusIcon: View {
  let kind: ChangeKind

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 16, height: 16)
      .background(color, in: RoundedRectangle(cornerRadius: 3.5))
      .help(String(describing: kind))
  }

  private var symbol: String {
    switch kind {
    case .modified, .typeChanged: "pencil"
    case .added, .intentToAdd: "plus"
    case .untracked: "questionmark"
    case .deleted: "minus"
    case .renamed, .copied: "arrow.right"
    case .unmerged: "exclamationmark"
    }
  }

  private var color: Color {
    switch kind {
    case .modified, .typeChanged: .orange
    case .added, .intentToAdd: .green
    case .untracked: .purple
    case .deleted: .red
    case .renamed, .copied: .blue
    case .unmerged: .red
    }
  }
}

private struct MultiSelectionPane: View {
  let model: RepositoryModel
  let changes: [WorkingCopyChange]

  var body: some View {
    VStack(spacing: 12) {
      Text("\(changes.count) files selected").font(.title3)
      HStack {
        let unstaged = changes.filter { $0.area == .unstaged }
        let staged = changes.filter { $0.area == .staged }
        Button("Stage \(unstaged.count)") { model.stage(unstaged) }.disabled(unstaged.isEmpty)
        Button("Unstage \(staged.count)") { model.unstage(staged) }.disabled(staged.isEmpty)
      }
      Text("Space toggles the selection between staged and unstaged.").font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct CommitComposer: View {
  @Bindable var model: RepositoryModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextEditor(text: $model.commitMessage)
        .font(.body)
        .frame(minHeight: 56, maxHeight: 120)
        .overlay(alignment: .topLeading) {
          if model.commitMessage.isEmpty {
            Text("Commit message").foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 1).allowsHitTesting(false)
          }
        }
      HStack {
        Toggle("Amend", isOn: $model.amend)
        Spacer()
        Text("\(model.status.staged.count) staged").foregroundStyle(.secondary).font(.caption)
        Button("Commit") { model.commit() }
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (model.status.staged.isEmpty && !model.amend))
      }
    }
    .padding(8)
  }
}

struct ChangeDiffPane: View {
  let model: RepositoryModel
  let change: WorkingCopyChange

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        StatusIcon(kind: change.kind)
        Text(change.path).font(.body.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        Spacer()
        switch change.area {
        case .unstaged: Button("Stage file") { model.stage(change) }
        case .staged: Button("Unstage file") { model.unstage(change) }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      Divider()
      if let file = model.diff(for: change) {
        DiffView(model: model, source: .change(change), file: file, hunkAction: hunkAction(for: file))
      } else if change.kind == .untracked {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
          .task(id: change.path) { await model.ensureUntrackedDiff(path: change.path) }
      } else {
        Text("No textual changes").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private func hunkAction(for file: FileDiff) -> DiffView.HunkAction {
    switch (change.area, change.kind) {
    case (.unstaged, .untracked):
      return DiffView.HunkAction(
        title: "Stage file", icon: "plus", perform: { _ in model.stage(change) },
        linesVerb: "Stage", performLines: { hunk, lines in model.stageLines(lines, of: hunk, in: file) }
      )
    case (.unstaged, _):
      return DiffView.HunkAction(
        title: "Stage hunk", icon: "plus", perform: { hunk in model.stageHunk(hunk, of: file) },
        linesVerb: "Stage", performLines: { hunk, lines in model.stageLines(lines, of: hunk, in: file) }
      )
    case (.staged, _):
      return DiffView.HunkAction(
        title: "Unstage hunk", icon: "minus", perform: { hunk in model.unstageHunk(hunk, of: file) },
        linesVerb: "Unstage", performLines: { hunk, lines in model.unstageLines(lines, of: hunk, in: file) }
      )
    }
  }
}
