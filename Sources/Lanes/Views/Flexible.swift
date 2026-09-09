import SwiftUI

/// Lays its content out at whatever size it is offered along the given axes and reports exactly
/// that, so the content's own minimum never propagates upward. A single-line `Text` reports its
/// full width as its minimum, a macOS `List` reports its widest row, and both would otherwise set
/// the window's minimum size (and, for a `List` queried during layout, keep changing it).
struct Flexible: Layout {
  let axes: Axis.Set

  init(_ axes: Axis.Set = .horizontal) {
    self.axes = axes
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let content = subviews.first else { return .zero }
    if axes == [.horizontal, .vertical] {
      let ideal = proposal.width == nil || proposal.height == nil ? content.sizeThatFits(.unspecified) : .zero
      return CGSize(width: proposal.width ?? ideal.width, height: proposal.height ?? ideal.height)
    }
    if axes == .horizontal {
      let width = proposal.width ?? content.sizeThatFits(.unspecified).width
      let height = content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
      return CGSize(width: width, height: height)
    }
    let height = proposal.height ?? content.sizeThatFits(.unspecified).height
    let width = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: height)).width
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(
      at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
    )
  }
}
