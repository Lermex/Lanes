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
      }
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
        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(presentation.rows) { row in
              switch row {
              case .hunkHeader(let hunk):
                HunkHeaderRow(
                  hunk: hunk, action: hunkAction, colors: colors, selectedCount: selectedIndices(in: hunk).count,
                  performLines: { hunkAction?.performLines?(hunk, selectedIndices(in: hunk)) },
                  clearSelection: { selectedLines = selectedLines.filter { $0.hunk != hunk.index } }
                )
              case .line(let hunk, let line, let text):
                let ref = LineRef(hunk: hunk.index, line: line.index)
                let selectable = supportsLineSelection && (line.kind == .added || line.kind == .removed)
                DiffLineRow(
                  line: line, text: text, colors: colors, isSelected: selectedLines.contains(ref),
                  selectableText: !supportsLineSelection
                )
                .contentShape(Rectangle())
                .onTapGesture { if selectable { handleTap(ref, in: hunk) } }
                .accessibilityElement(children: selectable ? .ignore : .contain)
                .accessibilityLabel(selectable ? lineLabel(line) : "")
                .accessibilityAddTraits(selectable ? .isButton : [])
                .accessibilityAction { if selectable { handleTap(ref, in: hunk) } }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
        .foregroundStyle(textStyle)
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
