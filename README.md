# Lanes

A small native macOS git client built around two things other clients get wrong:

* a SourceTree-style commit graph where you choose which branches are drawn, and the choice is
  remembered per repository
* a staging area that stages hunk by hunk, with tree-sitter syntax highlighting in the diff

Everything else (fetch, push, rebase, …) stays in the terminal.

## Building

Requires Xcode 26 and macOS 26.

```sh
make app                 # release build → Build/Lanes.app
make app CONFIG=debug    # debug build
make run REPO=/path/to/repo
make test
```

`Package.swift` is a plain SwiftPM manifest, so the package also opens directly in Xcode.

Git is driven through the `git` executable (Homebrew's if present, else `/usr/bin/git`) using its
machine-readable formats, so behaviour matches the CLI exactly: hooks run on commit, attributes and
filters apply, and worktrees just work.

## Layout

* `Sources/GitCore` — process runner, parsers for `for-each-ref` / `log` / `status --porcelain=v2` /
  unified diffs, single-hunk patch building (`git apply --cached`), the graph lane layouts (classic
  and trunk view), and an FSEvents watcher
* `Sources/Highlighting` — tree-sitter grammars behind a file-extension registry, and a highlighter
  that turns a whole file into per-line styled runs (tree-sitter precedence: later patterns win for
  the same node, inner nodes override outer ones)
* `Sources/GrammarScanners` — copies of the external scanners for JavaScript, Python, YAML and CSS,
  whose upstream manifests fail to compile them under SwiftPM 6 (`make sync-scanners` refreshes
  them; those four grammars are pinned to exact versions)
* `Sources/Lanes` — the SwiftUI app: sidebar with per-branch checkboxes and a Remotes menu,
  history list with a Canvas-drawn graph cell per row and draggable column dividers, the
  working-copy view (unstaged / staged / commit box) and the commit-detail view

## Behaviour worth knowing

* The Changes screen is one dense list: a Staged files section and an Unstaged files section, each
  row with a checkbox (checked = staged; toggling it stages or unstages), a status icon, the full
  path, and a … menu (stage/unstage, copy path, reveal in Finder). The section header checkbox
  stages or unstages the whole section, the list supports multi-selection with Space toggling the
  selection, double-click toggles a row, and the list sorts by path, file name or status.
* Line staging: in a staging diff, click a changed line to select it, shift-click to extend, ⌘-click
  to toggle; the hunk header then offers "Stage N lines" (or Unstage; Return triggers it) and Clear.
  Unselected removals stay in place, unselected additions are left unstaged, and the same works for
  untracked files (only the chosen lines enter the index). Text selection is disabled in staging
  diffs so that clicks select lines; commit diffs keep selectable text.
* Two modes, switched with the toolbar segment or ⌘1 / ⌘2: History (graph on top, commit or
  working-copy detail below) and Changes (the staging area on its own, sidebar collapsed).
* History columns resize by dragging the dividers in the header; widths persist. The graph column
  defaults to fitting every lane; double-click its divider or use View › Fit Graph Column (⇧⌘G)
  to return to that.
* The Remotes menu in the sidebar hides a whole remote: its branches leave the sidebar, the graph
  revisions, and the ref chips. Hidden remotes are listed at the bottom of the sidebar with a
  Show link. This is stored with the branch filter.
* Trunk view (toolbar toggle, View › Trunk View, ⌥⌘T) draws only the trunk as a lane and collapses
  every other branch into a capsule row placed directly above the trunk commit it forked from, with
  its refs, PR badge, commit count and how far behind the trunk it is. The chevron (or a
  double-click) expands a capsule into its commits, which render inline in the side lane without
  moving anything else. Branches merged into the trunk appear the same way, spanning from their
  merge commit. The trunk defaults to `origin/master` (or `origin/main`), can be changed with
  "Use as Trunk" in a branch's context menu, and never follows HEAD; checking out a branch expands
  its capsule instead. Trunk choice and expansion state are stored per repository.
* The sidebar's Select row (None / Local / With PRs) rewrites the branch selection; With PRs turns
  on every branch with an open pull request (View › Show Branches With Pull Requests, ⇧⌘P), adding
  to the current selection unless show-all was on.
* Fetch (toolbar, or Repository › Fetch, ⇧⌘F) runs `git fetch --all --prune` and refreshes.
* Open pull requests come from `gh pr list` (GitHub CLI, Homebrew or /usr/local) and show as a
  `#123` badge next to the branch in the sidebar and on graph rows; click to open. Refreshed at
  most once a minute, or on ⌘R. No gh, no GitHub remote, or no auth just means no badges.

* Branch filter state is stored in `UserDefaults` under `branchFilter:<common git dir>`, so all
  worktrees of a repository share it. The checked-out branch is always shown.
* Nested git repositories (directories with their own `.git`, which git reports as a single
  untracked `dir/`) are hidden from the Unstaged list.
* Untracked files and intent-to-add entries (`git add -N`) both appear in the Unstaged list, so a
  review flow that keeps new files unstaged until reviewed sees them.
* Rename detection is off for the working copy (a rename shows as delete + add) so that every hunk
  is stageable; commit diffs use rename detection.
* Syntax colours come from Zed theme files: the app bundles `Resources/Themes/lermex-intellij.json`
  (selected by default) and also reads `~/Library/Application Support/Lanes/Themes/*.json` and
  `~/.config/zed/themes/*.json`. Pick one in Settings (⌘,), or "System" for the built-in adaptive
  pair. A theme's `syntax` map is looked up by scope with fallback (`keyword.return` → `keyword`);
  the grammars' nvim-style capture names are normalised to Zed's vocabulary first. The theme's
  editor background/foreground, diff hunk backgrounds and line-number colour are applied to the
  diff pane too. TypeScript/TSX queries are composed with JavaScript's, as the grammar's own
  `tree-sitter.json` does.
* Highlighting parses the full old and new versions of a file (index, worktree, or blob), so
  removed lines are coloured from the old file and added lines from the new one.
* Setting `LANES_DEBUG=1` prints a state summary to stderr after each refresh. Setting
  `LANES_SNAPSHOT_DIR=<dir>` adds a Debug › Snapshot Window command (⇧⌘D) that writes the window
  as a PNG there without needing Screen Recording permission (glass and sidebar vibrancy render
  blank in it).
* Quit the app normally rather than killing it: after a kill, macOS treats the next launch as a
  resume and SwiftUI restores windows instead of opening the default one.
* SQL has no grammar yet: `tree-sitter-sql` publishes its 41 MB generated parser only outside its
  tagged sources.
* Do not launch the app with a bare path argument; AppKit treats it as a document to open and
  SwiftUI then never opens the main window. Use `--repo=<path>` (what `make run` does).
