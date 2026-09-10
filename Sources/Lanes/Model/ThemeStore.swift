import AppKit
import Foundation
import Highlighting
import Observation
import SwiftUI

/// Syntax themes are chosen per appearance, so the diff pane follows the system when it switches
/// between light and dark on its own.
@MainActor
@Observable
final class ThemeStore {
  static let defaultDarkSelection = "LermexIntellij"
  static let defaultLightSelection = "Stark Light"
  private static let darkKey = "syntaxTheme.dark"
  private static let lightKey = "syntaxTheme.light"
  private static let legacyKey = "syntaxTheme"

  private(set) var themes: [SyntaxTheme] = []
  private(set) var loadErrors: [String] = []
  var darkSelection: String {
    didSet { UserDefaults.standard.set(darkSelection, forKey: Self.darkKey) }
  }
  var lightSelection: String {
    didSet { UserDefaults.standard.set(lightSelection, forKey: Self.lightKey) }
  }

  init() {
    let defaults = UserDefaults.standard
    darkSelection = defaults.string(forKey: Self.darkKey) ?? Self.defaultDarkSelection
    lightSelection = defaults.string(forKey: Self.lightKey) ?? Self.defaultLightSelection
    reload()
    migrateSingleSelection(defaults)
  }

  /// Earlier versions stored one theme for both appearances; it keeps applying to the appearance it was made for.
  private func migrateSingleSelection(_ defaults: UserDefaults) {
    guard let legacy = defaults.string(forKey: Self.legacyKey) else { return }
    defaults.removeObject(forKey: Self.legacyKey)
    guard let theme = themes.first(where: { $0.name == legacy }) else { return }
    if theme.isDark {
      darkSelection = legacy
      defaults.set(legacy, forKey: Self.darkKey)
    } else {
      lightSelection = legacy
      defaults.set(legacy, forKey: Self.lightKey)
    }
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
    let selection = isDark ? darkSelection : lightSelection
    return themes.first { $0.name == selection } ?? (isDark ? .lanesDark : .lanesLight)
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
      themePicker("Dark mode theme", selection: $store.darkSelection, isDark: true)
      themePicker("Light mode theme", selection: $store.lightSelection, isDark: false)
      Text("Each applies while the app is in that appearance, so a system set to switch automatically switches the syntax colours too.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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

  /// Themes made for the appearance come first; the others are still offered, marked with theirs.
  private func themePicker(_ title: String, selection: Binding<String>, isDark: Bool) -> some View {
    Picker(title, selection: selection) {
      ForEach(store.themes.filter { $0.isDark == isDark }) { theme in
        Text(theme.name).tag(theme.name)
      }
      Divider()
      ForEach(store.themes.filter { $0.isDark != isDark }) { theme in
        Text("\(theme.name) (\(theme.isDark ? "dark" : "light"))").tag(theme.name)
      }
    }
  }
}
