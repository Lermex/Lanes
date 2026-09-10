import AppKit
import GitCore
import SwiftUI

/// Items of a branch's context menu, shared by the sidebar rows, capsule rows and ref chips.
struct BranchMenuItems: View {
  let model: RepositoryModel
  let ref: Ref

  var body: some View {
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
      Button("Rename \(ref.branchName)…") { model.branchToRename = ref }
    }
    Button(ref.remote.map { "Delete \(ref.branchName) from \($0)…" } ?? "Delete \(ref.branchName)…", role: .destructive) {
      model.branchToDelete = ref
    }
    .disabled(ref.isHead)
    Divider()
    Button("Use as Trunk") { model.setTrunk(ref) }
      .disabled(model.trunkRef?.fullName == ref.fullName)
  }
}

/// Menu items for the refs sitting on a commit or capsule: a lone branch's items inline, several
/// branches as submenus named after them, and a delete item per tag.
struct RefMenuItems: View {
  let model: RepositoryModel
  let names: [String]

  private var refs: [Ref] {
    names.compactMap { model.ref(named: $0) }.filter { !$0.branchName.hasSuffix("HEAD") }
  }

  var body: some View {
    let branches = refs.filter { $0.kind != .tag }
    let tags = refs.filter { $0.kind == .tag }
    if branches.count == 1, let branch = branches.first {
      BranchMenuItems(model: model, ref: branch)
    } else {
      ForEach(branches) { branch in
        Menu(branch.shortName) { BranchMenuItems(model: model, ref: branch) }
      }
    }
    ForEach(tags) { tag in
      Button("Delete Tag \(tag.shortName)…", role: .destructive) { model.branchToDelete = tag }
    }
  }
}

/// Items of a commit's context menu in the history.
struct CommitMenuItems: View {
  let model: RepositoryModel
  let commit: Commit

  var body: some View {
    Button("Check Out Commit") { model.checkout(commit) }
      .disabled(model.head.sha == commit.sha)
    Button("New Branch Here…") { model.commitForNewBranch = commit }
    Button("Tag…") { model.commitToTag = commit }
    Divider()
    Button("Cherry-pick") { model.cherryPick(commit) }
    Button("Revert") { model.revert(commit) }
    Button("Reset \(model.head.branch ?? "HEAD") to Here…", role: .destructive) { model.commitToResetTo = commit }
    Divider()
    Button("Copy SHA") { Pasteboard.copy(commit.sha) }
    Button("Copy Message") { Pasteboard.copy(commit.body.isEmpty ? commit.subject : commit.subject + "\n\n" + commit.body) }
    if let url = model.webURL(for: commit) {
      Button("Open on GitHub") { NSWorkspace.shared.open(url) }
    }
  }
}

enum Pasteboard {
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

/// The alerts and confirmations behind the context menus, attached once to the repository view.
struct RepositoryDialogs: ViewModifier {
  @Bindable var model: RepositoryModel
  @State private var newName = ""

  func body(content: Content) -> some View {
    content
      .alert("Rename Branch", isPresented: presenting($model.branchToRename)) {
        TextField("New name", text: $newName)
        Button("Rename") {
          if let ref = model.branchToRename { model.rename(ref, to: newName) }
        }
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Rename “\(model.branchToRename?.shortName ?? "")”.")
      }
      .confirmationDialog(
        "Delete “\(model.branchToDelete?.shortName ?? "")”?", isPresented: presenting($model.branchToDelete), titleVisibility: .visible
      ) {
        Button(model.branchToDelete?.kind == .remoteBranch ? "Delete on Remote" : "Delete", role: .destructive) {
          guard let ref = model.branchToDelete else { return }
          Task { if await !model.delete(ref, force: false) { model.branchToForceDelete = ref } }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        if let remote = model.branchToDelete?.remote {
          Text("The branch is removed from \(remote).")
        } else if model.branchToDelete?.kind == .tag {
          Text("The tag is removed locally; a copy already pushed to a remote stays there.")
        } else {
          Text("The local branch is removed. Git refuses if it has unmerged commits; you can force it then.")
        }
      }
      .confirmationDialog(
        "“\(model.branchToForceDelete?.shortName ?? "")” is not fully merged", isPresented: presenting($model.branchToForceDelete),
        titleVisibility: .visible
      ) {
        Button("Delete Anyway", role: .destructive) {
          guard let ref = model.branchToForceDelete else { return }
          Task { _ = await model.delete(ref, force: true) }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its commits are not reachable from its upstream or HEAD; deleting it may lose them.")
      }
      .alert("New Branch", isPresented: presenting($model.commitForNewBranch)) {
        TextField("Branch name", text: $newName)
        Button("Create and Switch") {
          if let commit = model.commitForNewBranch { model.createBranch(named: newName, at: commit, switchTo: true) }
        }
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Create") {
          if let commit = model.commitForNewBranch { model.createBranch(named: newName, at: commit, switchTo: false) }
        }
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Starts at \(model.commitForNewBranch?.shortSha ?? "") “\(model.commitForNewBranch?.subject ?? "")”.")
      }
      .alert("New Tag", isPresented: presenting($model.commitToTag)) {
        TextField("Tag name", text: $newName)
        Button("Tag") {
          if let commit = model.commitToTag { model.createTag(named: newName, at: commit) }
        }
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Tags \(model.commitToTag?.shortSha ?? "") “\(model.commitToTag?.subject ?? "")”.")
      }
      .confirmationDialog(
        "Reset \(model.head.branch ?? "HEAD") to \(model.commitToResetTo?.shortSha ?? "")?", isPresented: presenting($model.commitToResetTo),
        titleVisibility: .visible
      ) {
        Button("Soft: keep changes staged") { reset(.soft) }
        Button("Mixed: keep changes unstaged") { reset(.mixed) }
        Button("Hard: discard changes", role: .destructive) { reset(.hard) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Moves \(model.head.branch ?? "HEAD") to “\(model.commitToResetTo?.subject ?? "")”. Later commits stay reachable only through the reflog.")
      }
      .onChange(of: model.branchToRename) { _, ref in if let ref { newName = ref.shortName } }
      .onChange(of: model.commitForNewBranch) { _, commit in if commit != nil { newName = "" } }
      .onChange(of: model.commitToTag) { _, commit in if commit != nil { newName = "" } }
  }

  private func reset(_ mode: ResetMode) {
    if let commit = model.commitToResetTo { model.reset(to: commit, mode: mode) }
  }

  private func presenting<T>(_ value: Binding<T?>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
  }
}
