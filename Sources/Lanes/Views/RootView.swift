import GitCore
import SwiftUI

struct RootView: View {
  @State private var state = WindowState()

  var body: some View {
    let _ = debugLog("RootView.body model=\(state.model != nil)")
    Group {
      if let model = state.model {
        RepositoryView(model: model)
      } else {
        WelcomeView(state: state)
      }
    }
    .focusedSceneValue(\.windowState, state)
    .task { await openLaunchArgumentIfNeeded() }
  }

  private func openLaunchArgumentIfNeeded() async {
    guard let path = LaunchArguments.takeRepositoryPath() else { return }
    await state.open(URL(fileURLWithPath: path, isDirectory: true))
  }
}

@MainActor
enum LaunchArguments {
  private static var consumed = false

  static func takeRepositoryPath() -> String? {
    guard !consumed else { return nil }
    consumed = true
    // a bare path argument would be treated by AppKit as a document to open, which suppresses the initial window
    return CommandLine.arguments.lazy.compactMap { $0.hasPrefix("--repo=") ? String($0.dropFirst("--repo=".count)) : nil }.first
  }
}

struct WelcomeView: View {
  let state: WindowState
  @State private var recents = RecentRepositories.load()

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)
      Text("Lanes").font(.largeTitle.weight(.semibold))
      Button("Open Repository…") { state.chooseAndOpen() }
        .keyboardShortcut("o", modifiers: .command)
        .controlSize(.large)
      if !recents.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recent").font(.headline).foregroundStyle(.secondary)
          ForEach(recents, id: \.path) { url in
            Button {
              Task { await state.open(url) }
            } label: {
              HStack {
                Image(systemName: "folder")
                Text(url.lastPathComponent)
                Text(url.deletingLastPathComponent().path).foregroundStyle(.secondary).lineLimit(1)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .frame(maxWidth: 520)
      }
      if let error = state.openError {
        Text(error).foregroundStyle(.red).frame(maxWidth: 520)
      }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      guard let provider = providers.first else { return false }
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url else { return }
        Task { @MainActor in await state.open(url) }
      }
      return true
    }
  }
}
