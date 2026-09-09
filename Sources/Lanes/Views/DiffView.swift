import GitCore
import Highlighting
import SwiftUI

struct DiffColors {
  let background: Color?
  let foreground: Color?
  let added: Color
  let removed: Color
  let hunkHeader: Color
  let lineNumber: Color?
  let addedMarker: Color
  let removedMarker: Color

  init(theme: SyntaxTheme) {
    background = theme.editorBackground.map(Theme.color)
    foreground = theme.editorForeground.map(Theme.color)
    added = theme.addedBackground.map(Theme.color) ?? Theme.addedLineBackground
    removed = theme.removedBackground.map(Theme.color) ?? Theme.removedLineBackground
    hunkHeader = theme.hunkHeaderBackground.map(Theme.color) ?? Theme.hunkHeaderBackground
    lineNumber = theme.lineNumber.map(Theme.color)
    addedMarker = theme.addedMarker.map(Theme.color) ?? Theme.addedMarker
    removedMarker = theme.removedMarker.map(Theme.color) ?? Theme.removedMarker
  }
}

struct LineRef: Hashable {
  let hunk: Int
  let line: Int
}

/// Frames of the currently laid-out diff rows, kept outside SwiftUI state so recording them
/// doesn't re-render the view; only read while a drag is in progress.
@MainActor
final class LineFrames {
  private var frames: [LineRef: CGRect] = [:]

  func set(_ ref: LineRef, _ frame: CGRect) { frames[ref] = frame }
  func reset() { frames = [:] }

  func line(atY y: CGFloat, inHunk hunk: Int) -> LineRef? {
    if let exact = frames.first(where: { $0.key.hunk == hunk && $0.value.minY <= y && y < $0.value.maxY })?.key { return exact }
    let sameHunk = frames.filter { $0.key.hunk == hunk }
    return sameHunk.min { abs($0.value.midY - y) < abs($1.value.midY - y) }?.key
  }
}

struct DiffView: View {
  struct HunkAction {
    let title: String
    let icon: String
    let perform: (Hunk) -> Void
    var linesVerb: String? = nil
    var performLines: ((Hunk, Set<Int>) -> Void)? = nil
  }

  let model: RepositoryModel
  let source: DiffSource
  let file: FileDiff
  let hunkAction: HunkAction?
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedLines: Set<LineRef> = []
  @State private var anchor: LineRef?
  @State private var scroll = ScrollState()
  @State private var frames = LineFrames()
  @State private var dragAnchor: LineRef?
  @State private var dragMoved = false
  @State private var selectionBeforeDrag: Set<LineRef> = []

  private static let contentSpace = "diffContent"

  private struct ScrollState: Equatable {
    var offsetX: CGFloat = 0
    var viewportWidth: CGFloat = 0
  }

  private static let gutterWidth: CGFloat = 44 + 44 + 6 + 12

  private var theme: SyntaxTheme { themeStore.theme(isDark: colorScheme == .dark) }
  private var colors: DiffColors { DiffColors(theme: theme) }

  private var presentation: DiffPresentation {
    model.presentations[DiffPresentation.Key(source: source, file: file, theme: theme)] ?? .plain(source: source, file: file, theme: theme)
  }

  var body: some View {
    content
      .background(colors.background ?? .clear)
      .task(id: DiffPresentation.Key(source: source, file: file, theme: theme)) {
        await model.ensurePresentation(for: source, file: file, theme: theme)
      }
      .onChange(of: file) {
        selectedLines = []
        anchor = nil
        frames.reset()
      }
  }

  private func range(from start: LineRef, to end: LineRef, in hunk: Hunk) -> Set<LineRef> {
    let bounds = min(start.line, end.line)...max(start.line, end.line)
    return Set(hunk.changedLineIndices.filter(bounds.contains).map { LineRef(hunk: hunk.index, line: $0) })
  }

  private func dragChanged(_ value: DragGesture.Value, ref: LineRef, in hunk: Hunk) {
    let flags = NSEvent.modifierFlags
    if dragAnchor == nil {
      selectionBeforeDrag = selectedLines
      dragAnchor = flags.contains(.shift) && anchor?.hunk == ref.hunk ? anchor : ref
      dragMoved = false
    }
    guard let base = dragAnchor else { return }
    if abs(value.translation.height) > 3 || abs(value.translation.width) > 3 { dragMoved = true }
    guard dragMoved, let target = frames.line(atY: value.location.y, inHunk: hunk.index) else { return }
    let dragged = range(from: base, to: target, in: hunk)
    selectedLines = flags.contains(.command) || flags.contains(.shift) ? selectionBeforeDrag.union(dragged) : dragged
    anchor = base
  }

  private func dragEnded(ref: LineRef, in hunk: Hunk) {
    if !dragMoved { handleTap(ref, in: hunk) }
    dragAnchor = nil
    dragMoved = false
  }

  private var supportsLineSelection: Bool { hunkAction?.performLines != nil }

  private func selectedIndices(in hunk: Hunk) -> Set<Int> {
    Set(selectedLines.filter { $0.hunk == hunk.index }.map(\.line))
  }

  private func lineLabel(_ line: DiffLine) -> String {
    switch line.kind {
    case .added: "Select added line \(line.newLineNumber ?? 0)"
    case .removed: "Select removed line \(line.oldLineNumber ?? 0)"
    case .context, .noNewline: ""
    }
  }

  private func handleTap(_ ref: LineRef, in hunk: Hunk) {
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift), let anchor, anchor.hunk == ref.hunk {
      let range = min(anchor.line, ref.line)...max(anchor.line, ref.line)
      let inRange = hunk.changedLineIndices.filter(range.contains).map { LineRef(hunk: hunk.index, line: $0) }
      selectedLines.formUnion(inRange)
    } else if flags.contains(.command) {
      if selectedLines.contains(ref) { selectedLines.remove(ref) } else { selectedLines.insert(ref) }
      anchor = ref
    } else {
      selectedLines = selectedLines == [ref] ? [] : [ref]
      anchor = ref
    }
  }

  private var content: some View {
    Group {
      if file.isBinary {
        Text("Binary file").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if file.hunks.isEmpty {
        Text(file.headerLines.joined(separator: "\n"))
          .font(Theme.codeFont)
          .foregroundStyle(.secondary)
          .padding()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        let contentWidth = max(presentation.textWidth + Self.gutterWidth + 24, scroll.viewportWidth)
        ScrollView([.vertical, .horizontal]) {
          LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(presentation.sections) { section in
              let hunk = section.hunk
              Section {
                ForEach(section.lines) { entry in
                  let line = entry.line
                  let ref = LineRef(hunk: hunk.index, line: line.index)
                  let selectable = supportsLineSelection && (line.kind == .added || line.kind == .removed)
                  DiffLineRow(
                    line: line, text: entry.text, colors: colors, isSelected: selectedLines.contains(ref),
                    selectableText: !supportsLineSelection
                  )
                  .frame(width: contentWidth, alignment: .leading)
                  .contentShape(Rectangle())
                  .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { frames.set(ref, $0) }
                  .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.contentSpace))
                      .onChanged { value in if selectable { dragChanged(value, ref: ref, in: hunk) } }
                      .onEnded { _ in if selectable { dragEnded(ref: ref, in: hunk) } },
                    isEnabled: selectable
                  )
                  .accessibilityElement(children: selectable ? .ignore : .contain)
                  .accessibilityLabel(selectable ? lineLabel(line) : "")
                  .accessibilityAddTraits(selectable ? (selectedLines.contains(ref) ? [.isButton, .isSelected] : .isButton) : [])
                  .accessibilityAction { if selectable { handleTap(ref, in: hunk) } }
                }
              } header: {
                // the header keeps the viewport's width and follows the horizontal offset, so its buttons stay visible
                HunkHeaderRow(
                  hunk: hunk, action: hunkAction, colors: colors, selectedCount: selectedIndices(in: hunk).count,
                  performLines: { hunkAction?.performLines?(hunk, selectedIndices(in: hunk)) },
                  clearSelection: { selectedLines = selectedLines.filter { $0.hunk != hunk.index } }
                )
                .frame(width: max(scroll.viewportWidth, 200))
                .offset(x: scroll.offsetX)
                .frame(width: contentWidth, alignment: .leading)
              }
            }
          }
          .coordinateSpace(.named(Self.contentSpace))
        }
        .defaultScrollAnchor(.topLeading)
        .onScrollGeometryChange(for: ScrollState.self) { geometry in
          ScrollState(
            offsetX: max(0, geometry.contentOffset.x + geometry.contentInsets.leading),
            viewportWidth: geometry.containerSize.width
          )
        } action: { _, new in
          scroll = new
        }
      }
    }
  }
}

private struct HunkHeaderRow: View {
  let hunk: Hunk
  let action: DiffView.HunkAction?
  let colors: DiffColors
  let selectedCount: Int
  let performLines: () -> Void
  let clearSelection: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text(hunkRange)
        .font(Theme.codeFont)
        .foregroundStyle(.secondary)
      if !hunk.heading.isEmpty {
        Text(hunk.heading).font(Theme.codeFont).foregroundStyle(.tertiary).lineLimit(1)
      }
      Spacer()
      if let action, selectedCount > 0, let verb = action.linesVerb {
        Button("Clear", action: clearSelection)
          .controlSize(.small)
        Button {
          performLines()
        } label: {
          Label("\(verb) \(selectedCount) line\(selectedCount == 1 ? "" : "s")", systemImage: action.icon)
        }
        .controlSize(.small)
        .keyboardShortcut(.return, modifiers: [])
      } else if let action {
        Button {
          action.perform(hunk)
        } label: {
          Label(action.title, systemImage: action.icon)
        }
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(colors.hunkHeader)
  }

  private var hunkRange: String {
    "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
  }
}

private struct DiffLineRow: View {
  let line: DiffLine
  let text: AttributedString
  let colors: DiffColors
  var isSelected = false
  var selectableText = true

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Text(line.oldLineNumber.map(String.init) ?? "")
        .frame(width: 44, alignment: .trailing)
        .foregroundStyle(lineNumberStyle)
      Text(line.newLineNumber.map(String.init) ?? "")
        .frame(width: 44, alignment: .trailing)
        .padding(.trailing, 6)
        .foregroundStyle(lineNumberStyle)
      Text(String(line.prefix))
        .frame(width: 12)
        .foregroundStyle(markerColor)
      lineText
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 8)
        .foregroundStyle(textStyle)
      Spacer(minLength: 0)
    }
    .font(Theme.codeFont)
    .padding(.vertical, 1)
    .background(background)
    .overlay(alignment: .leading) {
      if isSelected {
        Rectangle().fill(Color.accentColor).frame(width: 3)
      }
    }
    .overlay { if isSelected { Color.accentColor.opacity(0.18) } }
  }

  @ViewBuilder
  private var lineText: some View {
    if selectableText {
      Text(text).textSelection(.enabled)
    } else {
      Text(text)
    }
  }

  private var textStyle: AnyShapeStyle {
    if line.kind == .noNewline { return AnyShapeStyle(.secondary) }
    return colors.foreground.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)
  }

  private var lineNumberStyle: AnyShapeStyle {
    colors.lineNumber.map { AnyShapeStyle($0.opacity(0.7)) } ?? AnyShapeStyle(.secondary)
  }

  private var background: Color {
    switch line.kind {
    case .added: colors.added
    case .removed: colors.removed
    case .context, .noNewline: .clear
    }
  }

  private var markerColor: Color {
    switch line.kind {
    case .added: colors.addedMarker
    case .removed: colors.removedMarker
    case .context, .noNewline: colors.lineNumber.map { $0.opacity(0.7) } ?? .secondary
    }
  }
}
