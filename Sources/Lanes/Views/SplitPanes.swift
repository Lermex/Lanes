import AppKit
import SwiftUI

/// A two-pane split drawn by SwiftUI with a draggable divider. Nested inside a NavigationSplitView
/// column on macOS 26, the AppKit-backed VSplitView and HSplitView add the floating sidebar's width
/// to each pane's minimum and the column adds it once more, which gave the window a 1545 pt
/// minimum width; this container reports the panes' real minimums.
struct SplitPanes<First: View, Second: View>: View {
  private let axis: Axis
  private let firstMinimum: CGFloat
  private let secondMinimum: CGFloat
  private let defaultFraction: CGFloat
  private let firstCollapsed: Bool
  private let first: () -> First
  private let second: () -> Second

  @AppStorage private var storedFirstLength: Double
  @State private var dragStart: CGFloat?
  @State private var total: CGFloat = 0

  private static var dividerThickness: CGFloat { 1 }
  private static var handleThickness: CGFloat { 9 }

  init(
    _ axis: Axis, storageKey: String, firstMinimum: CGFloat, secondMinimum: CGFloat, defaultFraction: CGFloat = 0.5,
    firstCollapsed: Bool = false, @ViewBuilder first: @escaping () -> First, @ViewBuilder second: @escaping () -> Second
  ) {
    self.axis = axis
    self.firstMinimum = firstMinimum
    self.secondMinimum = secondMinimum
    self.defaultFraction = defaultFraction
    self.firstCollapsed = firstCollapsed
    self.first = first
    self.second = second
    _storedFirstLength = AppStorage(wrappedValue: 0, storageKey)
  }

  var body: some View {
    SplitLayout(
      axis: axis, firstLength: firstCollapsed ? nil : firstLength, firstMinimum: firstMinimum, secondMinimum: secondMinimum,
      dividerThickness: Self.dividerThickness, handleThickness: Self.handleThickness
    ) {
      first().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
      second().frame(maxWidth: .infinity, maxHeight: .infinity)
      handle
    }
    .coordinateSpace(.named("splitPanes"))
    .onGeometryChange(for: CGFloat.self) { axis == .vertical ? $0.size.height : $0.size.width } action: { total = $0 }
  }

  private var firstLength: CGFloat {
    storedFirstLength > 0 ? CGFloat(storedFirstLength) : total * defaultFraction
  }

  private var handle: some View {
    Rectangle()
      .fill(.separator)
      .frame(width: axis == .horizontal ? Self.dividerThickness : nil, height: axis == .vertical ? Self.dividerThickness : nil)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .onHover { hovering in
        if hovering { (axis == .vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() }
      }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .named("splitPanes"))
          .onChanged { value in
            if dragStart == nil { dragStart = firstLength }
            let delta = axis == .vertical ? value.translation.height : value.translation.width
            storedFirstLength = Double(clamped((dragStart ?? 0) + delta))
          }
          .onEnded { _ in dragStart = nil }
      )
      .accessibilityLabel(axis == .vertical ? "Vertical split divider" : "Horizontal split divider")
  }

  private func clamped(_ length: CGFloat) -> CGFloat {
    let upper = max(firstMinimum, total - Self.dividerThickness - secondMinimum)
    return min(max(firstMinimum, length), upper)
  }
}

private struct SplitLayout: Layout {
  let axis: Axis
  /// nil collapses the first pane and hides the divider
  let firstLength: CGFloat?
  let firstMinimum: CGFloat
  let secondMinimum: CGFloat
  let dividerThickness: CGFloat
  let handleThickness: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let firstMin = firstLength == nil ? .zero : subviews[0].sizeThatFits(.zero)
    let secondMin = subviews[1].sizeThatFits(.zero)
    let along = (firstLength == nil ? 0 : max(firstMinimum, self.along(firstMin)) + dividerThickness)
      + max(secondMinimum, self.along(secondMin))
    let across = max(self.across(firstMin), self.across(secondMin))
    let minimum = axis == .vertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
    return CGSize(
      width: max(proposal.width ?? 1100, minimum.width),
      height: max(proposal.height ?? 700, minimum.height)
    )
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let total = along(bounds.size)
    let divider = firstLength == nil ? 0 : dividerThickness
    let first = firstLength.map { min(max(firstMinimum, $0), max(firstMinimum, total - divider - secondMinimum)) } ?? 0
    let second = max(0, total - first - divider)
    switch axis {
    case .vertical:
      subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: first))
      subviews[1].place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + first + divider), proposal: ProposedViewSize(width: bounds.width, height: second)
      )
      let handle = firstLength == nil
        ? CGRect(origin: bounds.origin, size: .zero)
        : CGRect(x: bounds.minX, y: bounds.minY + first + divider / 2 - handleThickness / 2, width: bounds.width, height: handleThickness)
      subviews[2].place(at: handle.origin, proposal: ProposedViewSize(handle.size))
    case .horizontal:
      subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: first, height: bounds.height))
      subviews[1].place(
        at: CGPoint(x: bounds.minX + first + divider, y: bounds.minY), proposal: ProposedViewSize(width: second, height: bounds.height)
      )
      let handle = firstLength == nil
        ? CGRect(origin: bounds.origin, size: .zero)
        : CGRect(x: bounds.minX + first + divider / 2 - handleThickness / 2, y: bounds.minY, width: handleThickness, height: bounds.height)
      subviews[2].place(at: handle.origin, proposal: ProposedViewSize(handle.size))
    }
  }

  private func along(_ size: CGSize) -> CGFloat { axis == .vertical ? size.height : size.width }
  private func across(_ size: CGSize) -> CGFloat { axis == .vertical ? size.width : size.height }
}
