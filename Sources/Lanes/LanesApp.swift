import AppKit
import GitCore
import SwiftUI

@main
struct LanesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var themeStore = ThemeStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(themeStore)
    }
    .defaultSize(width: 1400, height: 900)
    .restorationBehavior(.disabled)
    .commands {
      RepositoryCommands()
    }
    Settings {
      ThemeSettingsView(store: themeStore)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    debugLog("applicationDidFinishLaunching windows=\(NSApplication.shared.windows.count) userInfo=\(notification.userInfo ?? [:])")
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate()
  }
}

func debugLog(_ message: @autoclosure () -> String) {
  guard ProcessInfo.processInfo.environment["LANES_DEBUG"] != nil else { return }
  FileHandle.standardError.write(Data((message() + "\n").utf8))
}

@MainActor
@Observable
final class WindowState {
  var model: RepositoryModel?
  var openError: String?

  func open(_ url: URL) async {
    do {
      let info = try await RepositoryDiscovery.discover(at: url)
      RecentRepositories.remember(info.workTree)
      let model = RepositoryModel(info: info)
      self.model = model
      DebugDriver.runIfRequested(model: model)
      await model.refresh()
    } catch {
      openError = "\(url.path) is not a git repository: \(error)"
    }
  }

  func chooseAndOpen() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open Repository"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { await open(url) }
  }
}

struct WindowStateKey: FocusedValueKey {
  typealias Value = WindowState
}

extension FocusedValues {
  var windowState: WindowState? {
    get { self[WindowStateKey.self] }
    set { self[WindowStateKey.self] = newValue }
  }
}

struct RepositoryCommands: Commands {
  @FocusedValue(\.windowState) private var windowState

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Open Repository…") { windowState?.chooseAndOpen() }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(windowState == nil)
    }
    CommandGroup(after: .toolbar) {
      Button("History") { windowState?.model?.mode = .history }
        .keyboardShortcut("1", modifiers: .command)
        .disabled(windowState?.model == nil)
      Button("Changes") { windowState?.model?.mode = .changes }
        .keyboardShortcut("2", modifiers: .command)
        .disabled(windowState?.model == nil)
      Toggle("Trunk View", isOn: Binding(
        get: { windowState?.model?.trunkView.enabled ?? false },
        set: { windowState?.model?.trunkView.enabled = $0 }
      ))
        .keyboardShortcut("t", modifiers: [.command, .option])
        .disabled(windowState?.model == nil)
      Button("Expand All Branches") { windowState?.model?.expandAllGroups() }
        .disabled(windowState?.model?.isTrunkViewActive != true)
      Button("Collapse All Branches") { windowState?.model?.collapseAllGroups() }
        .disabled(windowState?.model?.isTrunkViewActive != true)
      Divider()
      Button("Show Branches With Pull Requests") { windowState?.model?.selectBranchesWithPullRequests() }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(windowState?.model == nil)
      Button("Fit Graph Column") { windowState?.model?.fitGraphColumn() }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(windowState?.model == nil)
      Divider()
      Button("Refresh") { Task { await windowState?.model?.refresh(force: true) } }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(windowState?.model == nil)
    }
    if WindowSnapshot.directory != nil {
      CommandMenu("Debug") {
        Button("Snapshot Window") { WindowSnapshot.capture() }
          .keyboardShortcut("d", modifiers: [.command, .shift])
      }
    }
    CommandMenu("Repository") {
      Button("Fetch") { windowState?.model?.fetch() }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .disabled(windowState?.model == nil)
    }
    CommandMenu("Stage") {
      Button("Stage All") { windowState?.model?.stageAll() }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(windowState?.model == nil)
      Button("Unstage All") { windowState?.model?.unstageAll() }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        .disabled(windowState?.model == nil)
    }
  }
}
