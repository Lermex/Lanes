import GitCore
import SwiftUI

struct HistoryItem: Identifiable {
  enum Kind {
    case workingCopy(count: Int, lane: Int)
    case commit(Commit, row: GraphRow?, continuesFromWorkingCopy: Bool, hiddenDecorations: Set<String> = [])
    case capsule(BranchGroup, row: GraphRow)
  }

  let id: HistorySelection
  let kind: Kind
}

enum HistoryColumnWidths {
  static let graphKey = "historyGraphWidth"
  static let authorKey = "historyAuthorWidth"
  static let dateKey = "historyDateWidth"
  static let commitKey = "historyCommitWidth"
  static let gap: CGFloat = 9
  static let coordinateSpace = "history"
}



struct HistoryView: View {
  @Bindable var model: RepositoryModel
  @AppStorage(HistoryColumnWidths.graphKey) private var graphWidthSetting = 0.0
  @AppStorage(HistoryColumnWidths.authorKey) private var authorWidth = 150.0
  @AppStorage(HistoryColumnWidths.dateKey) private var dateWidth = 135.0
  @AppStorage(HistoryColumnWidths.commitKey) private var commitWidth = 80.0
  @State private var rowWidth: CGFloat?
  @State private var containerWidth: CGFloat?

  private var fitGraphWidth: CGFloat {
    let lanes = model.isTrunkViewActive ? (model.trunkLayout?.maxLaneCount ?? 1) : model.graph.maxLaneCount
    return CGFloat(max(lanes, 1)) * Theme.laneWidth + 10
  }

  private var graphWidth: CGFloat {
    graphWidthSetting > 0 ? CGFloat(graphWidthSetting) : fitGraphWidth
  }

  private var widths: RowWidths {
    RowWidths(graph: graphWidth, author: CGFloat(authorWidth), date: CGFloat(dateWidth), commit: CGFloat(commitWidth))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, headerInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
      Divider()
      ScrollViewReader { proxy in
        List(selection: $model.selection) {
          ForEach(items) { item in
            HistoryRow(item: item, widths: widths, model: model, measuredWidth: $rowWidth)
              .tag(item.id)
              .id(item.id)
          }
          if model.historyTruncated {
            Button("Load more commits…") { model.loadMoreHistory() }
              .buttonStyle(.link)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 6)
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, Theme.historyRowHeight)
        .onChange(of: model.selection) { _, selection in
          if let selection { proxy.scrollTo(selection, anchor: nil) }
        }
      }
    }
    .coordinateSpace(.named(HistoryColumnWidths.coordinateSpace))
  }

  // the List insets its rows symmetrically; the header lives outside the List and mirrors that inset
  private var headerInset: CGFloat {
    guard let rowWidth, let containerWidth else { return 0 }
    return max(0, (containerWidth - rowWidth) / 2)
  }

  private var header: some View {
    HStack(spacing: 0) {
      headerLabel("Graph").frame(width: graphWidth, alignment: .leading)
      ColumnResizer(
        width: Binding(get: { Double(graphWidth) }, set: { graphWidthSetting = $0 }),
        minimum: 30, growsToTheRight: true, reset: { graphWidthSetting = 0 }
      )
      headerLabel("Description").frame(maxWidth: .infinity, alignment: .leading)
      ColumnResizer(width: $authorWidth, minimum: 50, growsToTheRight: false, reset: { authorWidth = 150 })
      headerLabel("Author").frame(width: CGFloat(authorWidth), alignment: .leading)
      ColumnResizer(width: $dateWidth, minimum: 70, growsToTheRight: false, reset: { dateWidth = 135 })
      headerLabel("Date").frame(width: CGFloat(dateWidth), alignment: .leading)
      ColumnResizer(width: $commitWidth, minimum: 50, growsToTheRight: false, reset: { commitWidth = 80 })
      headerLabel("Commit").frame(width: CGFloat(commitWidth), alignment: .leading)
    }
    .padding(.horizontal, 8)
    .frame(height: 24)
  }

  private func headerLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }
}

struct RowWidths {
  let graph: CGFloat
  let author: CGFloat
  let date: CGFloat
  let commit: CGFloat
}

private struct ColumnResizer: View {
  @Binding var width: Double
  let minimum: Double
  let growsToTheRight: Bool
  let reset: () -> Void
  @State private var startWidth: Double?

  var body: some View {
    Rectangle()
      .fill(.clear)
      .frame(width: HistoryColumnWidths.gap)
      .overlay(Rectangle().fill(.separator).frame(width: 1))
      .contentShape(Rectangle())
      .onHover { inside in
        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
      }
      .onTapGesture(count: 2) { reset() }
      .gesture(
        DragGesture(minimumDistance: 2, coordinateSpace: .named(HistoryColumnWidths.coordinateSpace))
          .onChanged { value in
            let start = startWidth ?? width
            startWidth = start
            let delta = growsToTheRight ? value.translation.width : -value.translation.width
            width = max(minimum, start + delta)
          }
          .onEnded { _ in startWidth = nil }
      )
  }
}

private struct HistoryRow: View {
  let item: HistoryItem
  let widths: RowWidths
  let model: RepositoryModel
  @Binding var measuredWidth: CGFloat?

  var body: some View {
    content
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured in
        if measuredWidth != measured { measuredWidth = measured }
      }
      .listRowInsets(EdgeInsets())
      .listRowSeparator(.hidden)
  }

  private var content: some View {
    HStack(spacing: 0) {
      graphCell
        .frame(width: widths.graph, height: Theme.historyRowHeight)
        .clipped()
      gap
      description
        .frame(maxWidth: .infinity, alignment: .leading)
      gap
      author.frame(width: widths.author, alignment: .leading)
      gap
      date.frame(width: widths.date, alignment: .leading)
      gap
      sha.frame(width: widths.commit, alignment: .leading)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 8)
    .frame(height: Theme.historyRowHeight)
  }

  private var gap: some View { Spacer().frame(width: HistoryColumnWidths.gap) }

  @ViewBuilder
  private var graphCell: some View {
    switch item.kind {
    case .workingCopy(_, let lane):
      GraphCell(row: nil, workingCopyLane: lane, continuesFromWorkingCopy: false)
    case .commit(_, let row, let continues, _):
      GraphCell(row: row, workingCopyLane: nil, continuesFromWorkingCopy: continues)
    case .capsule(_, let row):
      GraphCell(row: row, workingCopyLane: nil, continuesFromWorkingCopy: false, nodeStyle: .capsule)
    }
  }

  @ViewBuilder
  private var description: some View {
    switch item.kind {
    case .workingCopy(let count, _):
      HStack(spacing: 8) {
        Text("Uncommitted changes").fontWeight(.medium)
        Text("\(count) file\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
      }
    case .commit(let commit, _, _, let hidden):
      HStack(spacing: 4) {
        ForEach(commit.decorations.filter { model.isDecorationVisible($0) && !hidden.contains($0) }, id: \.self) { decoration in
          RefChip(name: decoration, kind: model.refKinds[decoration], isHead: decoration == "HEAD")
          if model.refKinds[decoration] != .tag, let pullRequest = model.pullRequest(forBranchName: decoration) {
            PullRequestBadge(pullRequest: pullRequest)
          }
        }
        Text(commit.subject).lineLimit(1)
      }
    case .capsule(let group, _):
      CapsuleDescription(group: group, model: model)
    }
  }

  private var rowCommit: Commit? {
    switch item.kind {
    case .commit(let commit, _, _, _): commit
    case .capsule(let group, _): group.tip
    case .workingCopy: nil
    }
  }

  @ViewBuilder
  private var author: some View {
    if let commit = rowCommit { Text(commit.authorName).lineLimit(1) }
  }

  @ViewBuilder
  private var date: some View {
    if let commit = rowCommit {
      Text(commit.authorDate, format: .dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits).hour().minute())
        .monospacedDigit()
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private var sha: some View {
    if let commit = rowCommit { Text(commit.shortSha).font(.body.monospaced()) }
  }
}

private struct CapsuleDescription: View {
  let group: BranchGroup
  let model: RepositoryModel

  private var isExpanded: Bool { model.trunkView.expanded.contains(group.id) }

  var body: some View {
    HStack(spacing: 4) {
      Button {
        model.toggleGroup(group.id)
      } label: {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          .frame(width: 14)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel(isExpanded ? "Collapse \(group.names.first ?? "")" : "Expand \(group.names.first ?? "")")
      ForEach(group.names, id: \.self) { name in
        RefChip(name: name, kind: group.isMerged ? nil : model.refKinds[name], isHead: false)
      }
      if let pullRequest = group.names.lazy.compactMap({ model.pullRequest(forBranchName: $0) }).first {
        PullRequestBadge(pullRequest: pullRequest)
      }
      Text(summary).foregroundStyle(.secondary).lineLimit(1).fixedSize().layoutPriority(1)
      if !isExpanded, let tip = group.tip {
        Text(tip.subject).lineLimit(1).foregroundStyle(.tertiary)
      }
    }
  }

  private var summary: String {
    let count = "\(group.commits.count) commit\(group.commits.count == 1 ? "" : "s")"
    let behind = group.behind.map { ", \($0) behind" } ?? ", fork not loaded"
    return group.isMerged ? "\(count), merged" : count + behind
  }
}

extension HistoryView {
  private var items: [HistoryItem] {
    if model.isTrunkViewActive, let layout = model.trunkLayout {
      return trunkItems(layout)
    }
    let workingCopy: [HistoryItem] = model.status.isClean
      ? []
      : [HistoryItem(id: .workingCopy, kind: .workingCopy(count: model.status.changeCount, lane: model.graph.rows.first?.nodeLane ?? 0))]
    let commits = model.commits.enumerated().map { index, commit in
      HistoryItem(
        id: .commit(commit.sha),
        kind: .commit(
          commit,
          row: index < model.graph.rows.count ? model.graph.rows[index] : nil,
          continuesFromWorkingCopy: index == 0 && !model.status.isClean
        )
      )
    }
    return workingCopy + commits
  }

  private func trunkItems(_ layout: TrunkLayout) -> [HistoryItem] {
    let workingCopy: [HistoryItem] = model.status.isClean
      ? []
      : [HistoryItem(id: .workingCopy, kind: .workingCopy(count: model.status.changeCount, lane: 0))]
    let rows = layout.rows.map { row -> HistoryItem in
      switch row.kind {
      case .trunk(let commit):
        HistoryItem(id: .commit(commit.sha), kind: .commit(commit, row: row.graph, continuesFromWorkingCopy: false))
      case .branchCommit(let commit, let groupID):
        HistoryItem(
          id: .commit(commit.sha),
          kind: .commit(
            commit, row: row.graph, continuesFromWorkingCopy: false,
            hiddenDecorations: Set(layout.group(id: groupID)?.names ?? [])
          )
        )
      case .capsule(let group):
        HistoryItem(id: .branch(group.id), kind: .capsule(group, row: row.graph))
      }
    }
    return workingCopy + rows
  }
}

struct RefChip: View {
  let name: String
  let kind: RefKind?
  let isHead: Bool

  var body: some View {
    Text(name)
      .font(.caption.weight(.medium))
      .lineLimit(1)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.6), lineWidth: 1))
      .foregroundStyle(.primary)
  }

  private var color: Color {
    if isHead { return .green }
    switch kind {
    case .localBranch: return .blue
    case .remoteBranch: return .gray
    case .tag: return .yellow
    case nil: return .purple
    }
  }
}

enum GraphNodeStyle {
  case commit
  case capsule
}

struct GraphCell: View {
  let row: GraphRow?
  let workingCopyLane: Int?
  let continuesFromWorkingCopy: Bool
  var nodeStyle: GraphNodeStyle = .commit

  var body: some View {
    Canvas(rendersAsynchronously: false) { context, size in
      let midY = size.height / 2
      if let row {
        draw(row, in: &context, size: size, midY: midY)
      } else if let workingCopyLane {
        drawWorkingCopy(lane: workingCopyLane, in: &context, size: size, midY: midY)
      }
    }
  }

  private func x(_ lane: Int) -> CGFloat { Theme.laneWidth / 2 + CGFloat(lane) * Theme.laneWidth + 3 }

  private func draw(_ row: GraphRow, in context: inout GraphicsContext, size: CGSize, midY: CGFloat) {
    let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
    for transition in row.incoming {
      var path = Path()
      if transition.startsAtNode || transition.fromLane == transition.toLane {
        path.move(to: CGPoint(x: x(transition.toLane), y: 0))
        path.addLine(to: CGPoint(x: x(transition.toLane), y: midY))
      } else {
        path.move(to: CGPoint(x: x(transition.fromLane), y: 0))
        path.addCurve(
          to: CGPoint(x: x(transition.toLane), y: midY),
          control1: CGPoint(x: x(transition.fromLane), y: midY / 2),
          control2: CGPoint(x: x(transition.toLane), y: midY / 2)
        )
      }
      context.stroke(path, with: .color(Theme.graphColor(transition.colorIndex)), style: stroke)
    }
    for transition in row.outgoing {
      var path = Path()
      if transition.startsAtNode, transition.fromLane != transition.toLane {
        path.move(to: CGPoint(x: x(transition.fromLane), y: midY))
        path.addCurve(
          to: CGPoint(x: x(transition.toLane), y: size.height),
          control1: CGPoint(x: x(transition.fromLane), y: midY + midY / 2),
          control2: CGPoint(x: x(transition.toLane), y: midY + midY / 2)
        )
      } else {
        path.move(to: CGPoint(x: x(transition.fromLane), y: midY))
        path.addLine(to: CGPoint(x: x(transition.fromLane), y: size.height))
      }
      context.stroke(path, with: .color(Theme.graphColor(transition.colorIndex)), style: stroke)
    }
    if continuesFromWorkingCopy {
      var path = Path()
      path.move(to: CGPoint(x: x(row.nodeLane), y: 0))
      path.addLine(to: CGPoint(x: x(row.nodeLane), y: midY))
      context.stroke(path, with: .color(.secondary), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
    }
    let center = CGPoint(x: x(row.nodeLane), y: midY)
    let dot: Path =
      switch nodeStyle {
      case .commit: Path(ellipseIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
      case .capsule: Path(roundedRect: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11), cornerRadius: 3)
      }
    context.fill(dot, with: .color(Theme.graphColor(row.nodeColorIndex)))
    context.stroke(dot, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
  }

  private func drawWorkingCopy(lane: Int, in context: inout GraphicsContext, size: CGSize, midY: CGFloat) {
    var path = Path()
    path.move(to: CGPoint(x: x(lane), y: midY))
    path.addLine(to: CGPoint(x: x(lane), y: size.height))
    context.stroke(path, with: .color(.secondary), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
    let dot = Path(ellipseIn: CGRect(x: x(lane) - 4.5, y: midY - 4.5, width: 9, height: 9))
    context.stroke(dot, with: .color(.secondary), lineWidth: 2)
  }
}
