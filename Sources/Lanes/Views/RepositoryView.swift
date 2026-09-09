import GitCore
import SwiftUI

struct RepositoryView: View {
  @Bindable var model: RepositoryModel
  @State private var columnVisibility = NavigationSplitViewVisibility.all

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(model: model)
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
    } detail: {
      Group {
        switch model.mode {
        case .history:
          VSplitView {
            HistoryView(model: model)
              .frame(minHeight: 160)
            DetailView(model: model)
              .frame(minHeight: 200)
          }
        case .changes:
          WorkingCopyView(model: model)
        }
      }
      .overlay(alignment: .bottom) { errorBanner }
    }
    .navigationTitle(model.info.displayName)
    .navigationSubtitle(subtitle)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("View", selection: $model.mode) {
          Text("History").tag(ViewMode.history)
          Text(changesLabel).tag(ViewMode.changes)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      ToolbarItem(placement: .primaryAction) {
        Toggle(isOn: $model.trunkView.enabled) {
          Label("Trunk view", systemImage: "arrow.triangle.merge")
            .frame(height: 20)
        }
        .toggleStyle(.button)
        .help(trunkHelp)
        .disabled(model.trunkRef == nil)
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.fetch()
        } label: {
          Label("Fetch", systemImage: "arrow.down.circle")
            .frame(height: 20)
        }
        .help("Fetch all remotes (⇧⌘F)")
        .disabled(model.isBusy)
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await model.refresh(force: true) }
        } label: {
          if model.isRefreshing || model.isBusy {
            ProgressView()
              .controlSize(.small)
              .frame(width: 20, height: 20)
          } else {
            Image(systemName: "arrow.clockwise")
              .frame(width: 20, height: 20)
          }
        }
        .help("Refresh")
        .disabled(model.isRefreshing)
      }
    }
    .onChange(of: model.mode) { _, mode in
      columnVisibility = mode == .changes ? .detailOnly : .all
    }
  }

  private var trunkHelp: String {
    guard let trunk = model.trunkRef else { return "Trunk view needs a master or main branch" }
    return "Trunk view: collapse branches into capsules along \(trunk.shortName) (⌥⌘T)"
  }

  private var changesLabel: String {
    model.status.isClean ? "Changes" : "Changes (\(model.status.changeCount))"
  }

  private var subtitle: String {
    if let branch = model.head.branch { return branch }
    if let sha = model.head.sha { return "detached at \(sha.prefix(8))" }
    return "no commits"
  }

  @ViewBuilder
  private var errorBanner: some View {
    if let message = model.errorMessage {
      HStack(alignment: .top) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        Text(message).textSelection(.enabled).font(.callout)
        Spacer()
        Button {
          model.errorMessage = nil
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
      }
      .padding(10)
      .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
      .padding()
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}

struct PullRequestBadge: View {
  let pullRequest: PullRequest

  var body: some View {
    Button {
      NSWorkspace.shared.open(pullRequest.url)
    } label: {
      Text(verbatim: "#\(pullRequest.number)")
        .font(.caption.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
        .foregroundStyle(.primary)
    }
    .buttonStyle(.plain)
    .help(pullRequest.isDraft ? "Draft: \(pullRequest.title)" : pullRequest.title)
  }

  private var color: Color { pullRequest.isDraft ? .gray : .green }
}
