import AppKit
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
        case "snapshot": WindowSnapshot.capture()
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
      contentRect: NSRect(x: 200, y: 200, width: 300, height: 720), styleMask: [.titled], backing: .buffered, defer: false
    )
    window.title = "Sidebar preview"
    window.contentView = NSHostingView(rootView: SidebarView(model: model))
    window.makeKeyAndOrderFront(nil)
    sidebarWindow = window
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
