import AppKit
import GitCore
import QuartzCore
import SwiftUI

/// Scripted interactions for measuring rendering cost without a user at the keyboard. Enabled by
/// `LANES_DEBUG_SCRIPT`, a comma-separated list of steps: `changes`, `history`, `sidebar-scroll`,
/// `history-scroll`, `wait`. Each step logs how long the main thread needed to lay out and draw.
@MainActor
enum DebugDriver {
  static func runIfRequested(model: RepositoryModel) {
    guard let script = ProcessInfo.processInfo.environment["LANES_DEBUG_SCRIPT"] else { return }
    Task {
      try? await Task.sleep(for: .seconds(4))
      for step in script.split(separator: ",").map(String.init) {
        switch step {
        case "changes": await measure("switch to changes") { model.mode = .changes }
        case "history": await measure("switch to history") { model.mode = .history }
        case "sidebar-scroll": await scroll(tableWithRowsClosestTo: model.refs.count, label: "sidebar")
        case "history-scroll": await scroll(tableWithRowsClosestTo: model.commits.count, label: "history")
        case "wait": try? await Task.sleep(for: .seconds(2))
        case "check-updates": Updates.controller.updater.checkForUpdates()
        case let step where step.hasPrefix("reveal:"):
          let name = String(step.dropFirst("reveal:".count))
          if let ref = model.ref(named: name) { model.reveal(ref) } else { debugLog("reveal: no ref named \(name)") }
          try? await Task.sleep(for: .seconds(2))
          debugLog("reveal \(name): selection=\(String(describing: model.selection)) target=\(model.ref(named: name)?.target.prefix(7) ?? "")")
        case "trunk-on": model.trunkView.enabled = true
        case "trunk-off": model.trunkView.enabled = false
        case "settings":
          if let appMenu = NSApplication.shared.mainMenu?.items.first?.submenu,
            let index = appMenu.items.firstIndex(where: { $0.title.hasPrefix("Settings") })
          {
            appMenu.performActionForItem(at: index)
          } else {
            debugLog("settings: menu item not found")
          }
        case "snapshot-settings":
          let window = NSApplication.shared.windows.first { $0.title.hasSuffix("Settings") }
          if window == nil { debugLog("snapshot-settings: no settings window") }
          WindowSnapshot.capture(window: window)
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case let step where step.hasPrefix("select-path:"):
          model.selectedCommitPath = String(step.dropFirst("select-path:".count))
        case "collapse-all": model.collapseAllGroups()
        case let step where step.hasPrefix("expand:"):
          let name = String(step.dropFirst("expand:".count))
          if let group = model.trunkLayout?.groups.first(where: { $0.names.contains(name) }) { model.toggleGroup(group.id) }
        case "select-stash":
          if let stash = model.stashes.first { model.mode = .history; model.selection = .stash(stash.commit.sha) }
        case "git-env":
          let environment = await Git.subprocessEnvironment()
          let keys = ["GIT_ASKPASS", "SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "SSH_AUTH_SOCK", "GIT_TERMINAL_PROMPT"]
          debugLog("git env: " + keys.map { "\($0)=\(environment[$0].map { $0.hasPrefix("/") ? "<path>" : $0 } ?? "unset")" }.joined(separator: " "))
        case "snapshot": WindowSnapshot.capture()
        case "shrink": shrinkWindow()
        case "fit-min":
          if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            window.setContentSize(window.contentMinSize)
            debugLog("window resized to its minimum \(window.contentMinSize)")
          }
        case "minsize":
          if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            debugLog("window: \(window.frame.size) contentMinSize=\(window.contentMinSize)")
          }
        case "measure-views": measureViews(model: model)
        case "splits": logSplitViews()
        case "constraints": logWidthConstraints()
        case "sidebar-window": showSidebarWindow(model: model)
        case "snapshot-sidebar": WindowSnapshot.capture(window: sidebarWindow)
        default: debugLog("debug script: unknown step \(step)")
        }
      }
      debugLog("debug script: done")
    }
  }

  /// Hosts the sidebar in a plain window, whose contents the snapshot can capture (the real
  /// sidebar's glass renders blank), and makes it key so the next `snapshot` step picks it.
  private static var sidebarWindow: NSWindow?

  private static func showSidebarWindow(model: RepositoryModel) {
    let window = NSWindow(
      contentRect: NSRect(x: 200, y: 100, width: 300, height: 1000), styleMask: [.titled], backing: .buffered, defer: false
    )
    window.title = "Sidebar preview"
    window.contentView = NSHostingView(rootView: SidebarView(model: model))
    window.makeKeyAndOrderFront(nil)
    sidebarWindow = window
  }

  /// Logs each main view's minimum size (what it reports when offered zero space).
  private static func measureViews(model: RepositoryModel) {
    let themeStore = ThemeStore()
    func report<V: View>(_ name: String, _ view: V) {
      let controller = NSHostingController(rootView: view.environment(themeStore))
      let minimum = controller.sizeThatFits(in: .zero)
      let ideal = controller.sizeThatFits(in: NSSize(width: 10_000, height: 10_000))
      debugLog("min size of \(name): \(minimum) (ideal \(ideal))")
    }
    report("SidebarView", SidebarView(model: model))
    report("HistoryView", HistoryView(model: model))
    report("WorkingCopyView", WorkingCopyView(model: model))
    report("DetailView", DetailView(model: model))
    if let commit = model.commits.first {
      report("CommitDetailView", CommitDetailView(model: model, commit: commit))
    }
  }

  /// Logs every split view's panes with the widths they insist on, to find what sets the window minimum.
  private static func logSplitViews() {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible), let root = window.contentView else { return }
    func walk(_ view: NSView, depth: Int) {
      if let split = view as? NSSplitView {
        debugLog("split \(type(of: split)) vertical=\(split.isVertical) frame=\(split.frame.size)")
        for (index, pane) in split.arrangedSubviews.enumerated() {
          let hosting = firstHostingView(in: pane)
          debugLog("  pane \(index): \(type(of: pane)) width=\(pane.frame.width) fitting=\(pane.fittingSize.width) intrinsic=\(pane.intrinsicContentSize.width) hostingFitting=\(hosting?.fittingSize.width ?? -1) hosting=\(hosting.map { String(describing: type(of: $0)) } ?? "none")")
        }
      }
      for child in view.subviews { walk(child, depth: depth + 1) }
    }
    walk(root, depth: 0)
    debugLog("window contentMinSize=\(window.contentMinSize)")
  }

  /// Logs every width constraint on hosting views, scroll views and tables under the window.
  private static func logWidthConstraints() {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible), let root = window.contentView else { return }
    func walk(_ view: NSView, path: String) {
      let name = String(describing: type(of: view))
      let interesting = name.hasPrefix("NSHostingView") || view is NSScrollView || view is NSTableView || view is NSSplitView
      if interesting {
        let widths = view.constraints.filter { $0.firstAttribute == .width || $0.secondAttribute == .width }
        if !widths.isEmpty || view is NSTableView {
          debugLog("\(path)/\(name.prefix(40)) frame=\(Int(view.frame.width)) fitting=\(Int(view.fittingSize.width)) hugging=\(view.contentHuggingPriority(for: .horizontal).rawValue) compression=\(view.contentCompressionResistancePriority(for: .horizontal).rawValue)")
          for constraint in widths {
            debugLog("    \(constraint.relation == .greaterThanOrEqual ? ">=" : constraint.relation == .lessThanOrEqual ? "<=" : "==") \(Int(constraint.constant)) priority=\(constraint.priority.rawValue) active=\(constraint.isActive) id=\(constraint.identifier ?? "-")")
          }
          if let table = view as? NSTableView {
            debugLog("    table columns: \(table.tableColumns.map { "\(Int($0.width)) [min \(Int($0.minWidth)) max \(Int($0.maxWidth))]" }) rows=\(table.numberOfRows)")
          }
        }
      }
      for (index, child) in view.subviews.enumerated() { walk(child, path: path + "/" + String(index)) }
    }
    walk(root, path: "")
  }

  private static func firstHostingView(in view: NSView) -> NSView? {
    if String(describing: type(of: view)).hasPrefix("NSHostingView") { return view }
    for child in view.subviews {
      if let found = firstHostingView(in: child) { return found }
    }
    return nil
  }

  /// Asks the window to become small and logs what AppKit allowed, which is the effective minimum.
  private static func shrinkWindow() {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
    debugLog("window before: \(window.frame.size) minSize=\(window.minSize) contentMinSize=\(window.contentMinSize)")
    window.setContentSize(NSSize(width: 800, height: 500))
    window.contentView?.layoutSubtreeIfNeeded()
    debugLog("window after: \(window.frame.size) fitting=\(window.contentView?.fittingSize ?? .zero)")
  }

  private static func measure(_ label: String, _ change: () -> Void) async {
    let start = CACurrentMediaTime()
    change()
    await settle()
    debugLog("\(label): \(milliseconds(since: start)) ms")
  }

  /// Scrolls the table in steps of one viewport, timing each step, then jumps back to the top.
  private static func scroll(tableWithRowsClosestTo rows: Int, label: String) async {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
      let table = tables(in: window.contentView).min(by: { abs($0.numberOfRows - rows) < abs($1.numberOfRows - rows) }),
      let scrollView = table.enclosingScrollView
    else {
      debugLog("\(label) scroll: no table found")
      return
    }
    let clip = scrollView.contentView
    let height = clip.bounds.height
    let maxY = max(0, table.bounds.height - height)
    var times: [Double] = []
    var y: CGFloat = 0
    while y < maxY, times.count < 40 {
      y = min(y + height, maxY)
      let start = CACurrentMediaTime()
      clip.scroll(to: NSPoint(x: 0, y: y))
      scrollView.reflectScrolledClipView(clip)
      await settle()
      times.append(milliseconds(since: start))
    }
    clip.scroll(to: .zero)
    scrollView.reflectScrolledClipView(clip)
    await settle()
    let summary = times.map { String(format: "%.0f", $0) }.joined(separator: " ")
    debugLog("\(label) scroll (\(table.numberOfRows) rows, \(times.count) pages): max \(times.max().map { String(format: "%.0f", $0) } ?? "-") ms, avg \(String(format: "%.0f", times.reduce(0, +) / Double(max(times.count, 1)))) ms; per page: \(summary)")
  }

  private static func tables(in view: NSView?) -> [NSTableView] {
    guard let view else { return [] }
    return ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap { tables(in: $0) }
  }

  /// Forces layout and display, then waits one run loop turn so SwiftUI's commit has happened.
  private static func settle() async {
    if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
      window.contentView?.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
    }
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private static func milliseconds(since start: CFTimeInterval) -> Double {
    (CACurrentMediaTime() - start) * 1000
  }
}
