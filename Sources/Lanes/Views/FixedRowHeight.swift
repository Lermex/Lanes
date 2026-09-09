import AppKit
import SwiftUI

/// Tells the table behind a `List` that every row is `height` points tall. AppKit otherwise
/// measures each visible row through the Auto Layout engine whenever the table appears or
/// scrolls, which is what made the sidebar and the history list feel sluggish.
struct FixedRowHeight: NSViewRepresentable {
  let height: CGFloat

  func makeNSView(context: Context) -> Probe { Probe() }

  func updateNSView(_ probe: Probe, context: Context) {
    probe.height = height
    DispatchQueue.main.async { probe.apply() }
  }

  final class Probe: NSView {
    var height: CGFloat = 0

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // never mutate the table inside the layout pass that inserted this view
      DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    func apply() {
      guard let table = enclosingTable(), table.usesAutomaticRowHeights || table.rowHeight != height else { return }
      table.usesAutomaticRowHeights = false
      table.rowHeight = height
    }

    private func enclosingTable() -> NSTableView? {
      var ancestor = superview
      while let view = ancestor {
        if let table = Self.firstTable(in: view) { return table }
        ancestor = view.superview
      }
      return nil
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      for subview in view.subviews {
        if let table = firstTable(in: subview) { return table }
      }
      return nil
    }
  }
}

extension View {
  func fixedListRowHeight(_ height: CGFloat) -> some View {
    background(FixedRowHeight(height: height).frame(width: 0, height: 0))
  }
}
