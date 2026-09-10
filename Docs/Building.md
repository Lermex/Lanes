# Building

Requires Xcode 26 and macOS 26.

```sh
make app                 # release build → Build/Lanes.app
make app CONFIG=debug    # debug build
make run REPO=/path/to/repo
make test
make icon                # re-renders Resources/AppIcon/icon.svg into the .icns
```

`Package.swift` is a plain SwiftPM manifest, so the package also opens directly in Xcode.

Do not launch the app with a bare path argument; AppKit treats it as a document to open and
SwiftUI then never opens the main window. Use `--repo=<path>` (what `make run` does).

Locally, `make app SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` signs the bundle
the way the release workflow does (notarization is CI-only); see [Releasing](Releasing.md).

## Source layout

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

Git is driven through the `git` executable (Homebrew's if present, else `/usr/bin/git`) using its
machine-readable formats, so behaviour matches the CLI exactly: hooks run on commit, attributes and
filters apply, and worktrees just work.

SQL has no grammar yet: `tree-sitter-sql` publishes its 41 MB generated parser only outside its
tagged sources.
