import AppKit
import Foundation
import Highlighting
import Observation
import SwiftUI

@MainActor
@Observable
final class ThemeStore {
  static let systemSelection = "System"
  static let defaultSelection = "LermexIntellij"
  private static let selectionKey = "syntaxTheme"

  private(set) var themes: [SyntaxTheme] = []
  private(set) var loadErrors: [String] = []
  var selection: String {
    didSet { UserDefaults.standard.set(selection, forKey: Self.selectionKey) }
  }

  init() {
    selection = UserDefaults.standard.string(forKey: Self.selectionKey) ?? Self.defaultSelection
    reload()
  }

  var userThemesDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appending(path: "Lanes/Themes", directoryHint: .isDirectory)
  }

  var zedThemesDirectory: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".config/zed/themes", directoryHint: .isDirectory)
  }

  private var bundledThemesDirectories: [URL] {
    [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0?.appending(path: "Themes") }
  }

  func reload() {
    try? FileManager.default.createDirectory(at: userThemesDirectory, withIntermediateDirectories: true)
    var loaded: [SyntaxTheme] = [.lanesDark, .lanesLight]
    var errors: [String] = []
    for directory in bundledThemesDirectories + [userThemesDirectory, zedThemesDirectory] {
      let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
      for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        do {
          for theme in try ZedThemeFile.load(file) where !loaded.contains(where: { $0.name == theme.name }) {
            loaded.append(theme)
          }
        } catch {
          errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
        }
      }
    }
    themes = loaded
    loadErrors = errors
  }

  func theme(isDark: Bool) -> SyntaxTheme {
    if selection != Self.systemSelection, let chosen = themes.first(where: { $0.name == selection }) { return chosen }
    return isDark ? .lanesDark : .lanesLight
  }

  func openUserThemesDirectory() {
    reload()
    NSWorkspace.shared.open(userThemesDirectory)
  }
}

struct ThemeSettingsView: View {
  @Bindable var store: ThemeStore

  var body: some View {
    Form {
      Picker("Syntax theme", selection: $store.selection) {
        Text("System (Lanes Dark / Light)").tag(ThemeStore.systemSelection)
        Divider()
        ForEach(store.themes) { theme in
          Text("\(theme.name) (\(theme.isDark ? "dark" : "light"))").tag(theme.name)
        }
      }
      HStack {
        Button("Open Themes Folder") { store.openUserThemesDirectory() }
        Button("Reload") { store.reload() }
      }
      Text("Zed theme files (a `themes` array with a `syntax` map) are read from the app bundle, \(store.userThemesDirectory.path), and \(store.zedThemesDirectory.path).")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(store.loadErrors, id: \.self) { error in
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .padding(20)
    .frame(width: 520)
  }
}
