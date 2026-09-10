# Lanes

A small native macOS git client built around two things other clients get wrong:

* a SourceTree-style commit graph where you choose which branches are drawn, and the choice is
  remembered per repository
* a staging area that stages hunk by hunk, with tree-sitter syntax highlighting in the diff

Everything else (fetch, push, rebase, …) stays in the terminal.

## Installing

Builds are published to [GitHub Releases](https://github.com/Lermex/Lanes/releases) (see
[Releases](#releases) below). Unzip and move `Lanes.app` to Applications. Releases that were only
ad-hoc signed (see Signing and notarization) need the quarantine flag cleared once:

```sh
xattr -dr com.apple.quarantine /Applications/Lanes.app
```

## Building

Requires Xcode 26 and macOS 26.

```sh
make app                 # release build → Build/Lanes.app
make app CONFIG=debug    # debug build
make run REPO=/path/to/repo
make test
make icon                # re-renders Resources/AppIcon/icon.svg into the .icns
```

`Package.swift` is a plain SwiftPM manifest, so the package also opens directly in Xcode.

## Releases

Releases are cut by hand with the Release workflow (Actions › Release › Run workflow, or
`gh workflow run release.yml -f bump=patch`). It bumps the version from the latest `v*` tag (patch
by default; pick `minor` or `major`, or pass an explicit `version`), writes release notes listing
every commit since that tag grouped as Added / Changed / Fixed / Removed with a compare link
(`Scripts/release.swift`), runs the tests, builds the bundle stamped with that version, and publishes
the zip under the new tag. `dry_run=true` does everything except publish and keeps the zip and notes
as a workflow artifact. Pushes to `master` only run the tests (`.github/workflows/ci.yml`).

### Updates

The app updates itself with [Sparkle](https://sparkle-project.org): it checks
`https://github.com/Lermex/Lanes/releases/latest/download/appcast.xml` once a day and on
Lanes › Check for Updates…, and installs the zip from the release after verifying its EdDSA
signature and that it was signed by the same Developer ID. The release workflow writes that
`appcast.xml` (with the notes as HTML) using the `SPARKLE_PRIVATE_KEY` secret; the matching public
key is `SUPublicEDKey` in `Resources/Info.plist`. The private key also lives in the keychain of the
Mac that generated it, as "Private key for signing Sparkle updates". `LANES_UPDATE_FEED=<url>`
points a build at another appcast for trying updates locally.

### Signing and notarization

With four repository secrets in place the workflow signs the bundle with a Developer ID certificate
under the hardened runtime, notarizes it with Apple and staples the ticket, so downloads open
without the Gatekeeper dance. Without them it falls back to an ad-hoc signature.

1. Certificate: in Xcode › Settings › Accounts › Manage Certificates, add a **Developer ID
   Application** certificate. In Keychain Access, export it (with its private key) as a `.p12`
   with a password. Then
   `gh secret set MACOS_CERTIFICATE_P12 < <(base64 -i Certificates.p12)` and
   `gh secret set MACOS_CERTIFICATE_PASSWORD`.
2. Notarization key: in App Store Connect › Users and Access › Integrations › App Store Connect
   API, generate a team key with the Developer role and download its `.p8`. Then
   `gh secret set NOTARY_KEY_P8 < <(base64 -i AuthKey_XXXX.p8)`, `gh secret set NOTARY_KEY_ID` (the
   key's ID) and `gh secret set NOTARY_ISSUER_ID` (the issuer ID shown above the key list).

The identity name is read from the certificate, so nothing else needs configuring. Locally,
`make app SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` signs the same way
(notarization is CI-only).

## App icon

`Resources/AppIcon/icon.svg` is the source: the right half of a road seen from above, travelling
upward, with a lane merging in from the right. The shapes are plain SVG paths on an 824 px rounded
square centred on the 1024 px canvas (lane width 350 units between line centres, the two merge
curves concentric about (812, 250) so the merging lane keeps its width around the bend). The asphalt
grain, paint wear, wheel tracks and lighting are SVG filters and gradients in `<defs>`, each a
tunable number.

```sh
make icon
```

renders it: `Scripts/rendersvg.swift` rasterises the SVG through WebKit (the only Apple renderer
that runs the filters) onto a transparent 1024 px canvas, `sips` scales the iconset, and `iconutil`
writes `Resources/AppIcon.icns`, which the bundle ships. Commit the regenerated PNG and `.icns`
together with the SVG; CI does not render icons.

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
* Diffs scroll in both directions: lines keep their natural width, row backgrounds span the widest
  line, and hunk headers stay pinned at the top and follow the horizontal offset so their buttons
  remain in view.
* Line staging: in a staging diff, click a changed line to select it, drag to select a range,
  shift-click (or shift-drag) to extend, ⌘-click (or ⌘-drag) to add; the hunk header then offers "Stage N lines" (or Unstage; Return triggers it) and Clear.
  Unselected removals stay in place, unselected additions are left unstaged, and the same works for
  untracked files (only the chosen lines enter the index). Text selection is disabled in staging
  diffs so that clicks select lines; commit diffs keep selectable text.
* Two modes, switched with the toolbar segment or ⌘1 / ⌘2: History (graph on top, commit or
  working-copy detail below) and Changes (the staging area on its own, sidebar collapsed).
* The window's minimum size is what the staging area needs (about 930 pt wide with the sidebar),
  so it fits a 13-inch screen; on narrow windows the history columns scale down together so the
  description keeps at least 200 pt, and a fitted graph column takes at most 40 % of the list.
* In the graph, a commit that a branch points at is a rounded square; every other commit is a
  circle. This holds in both views, so a collapsed chain in the trunk view ends in a square only
  while a branch still points at its tip (merged-and-deleted or orphan groups end in a circle).
* History columns resize by dragging the dividers in the header; widths persist. The graph column
  defaults to fitting every lane; double-click its divider or use View › Fit Graph Column (⇧⌘G)
  to return to that.
* The sidebar has three groups, Branches, Tags and Stashes, each with a Mail-style header (title
  and a one-line summary) that collapses the whole group with its chevron and stays collapsed
  across launches. The Branches header keeps the controls behind two menus: the filter menu (≡,
  tinted while a filter is on) holds Show all branches, Show tags, Show in graph (None / Local
  branches / Branches with pull requests) and the Remotes submenu; the more menu (…) holds Sort
  by. Local branches come first, then each remote's branches under its name.
* Tags are sorted like the branches and offer Check Out and Delete Tag in their menu; Stashes
  offer Apply, Pop and Drop, and clicking one shows its diff in the detail pane. Stage › Stash
  Changes (⌃⌘S) stashes the working copy, untracked files included.
* Sort by orders every branch section by name, by whether the branch has an open pull request, by
  fork date (the date of the branch's merge base with the trunk), or by last commit. Date orders
  show a relative date on each row. Fork dates come from one `git merge-base` per branch tip,
  computed in the background after each refresh and remembered per tip.
* Right-click a commit in the history for Check Out Commit (detached), New Branch Here, Tag,
  Cherry-pick, Revert, Reset the current branch to it (soft, mixed or hard, after a confirmation),
  Copy SHA, Copy Message and Open on GitHub (when origin is a GitHub-style remote). Below those,
  every branch on the commit gets its actions (inline for one branch, a submenu per branch for
  several) and every tag a Delete Tag item, which asks whether to delete it locally only or also on
  the remotes; ref chips carry the same menu for their own ref, and
  capsule rows offer Expand / Collapse plus the menus of their branches.
* Right-click a branch in the sidebar for Switch (a remote branch gets a local tracking branch),
  Push (to the upstream's remote, or a chosen remote when the branch has no upstream yet, which
  then sets it), Rename, Delete, and Use as Trunk. Deleting asks first, and when the branch also
  exists on a remote (or a remote branch also exists locally) offers to delete it locally, on the
  remote, or both; if git refuses because the branch is not fully merged you are asked again
  before it is forced.
* Unchecking a remote in the Remotes submenu hides it whole: its branches leave the sidebar, the
  graph revisions, and the ref chips. This is stored with the branch filter.
* Trunk view (toolbar toggle, View › Trunk View, ⌥⌘T) draws only the trunk as a lane and collapses
  every other branch into a capsule row placed directly above the trunk commit it forked from, with
  its refs, PR badge, commit count and how far behind the trunk it is; the graph draws the
  collapsed branch's commits as a chain growing to the right, oldest at the trunk and the tip at
  the end, eliding the middle when the column is narrow (View › Show Commits in Collapsed Branches
  turns the chains off). The chevron expands a capsule into its commits, which render inline in
  the side lane without moving anything else; the latest commit is then the top row and carries
  the refs, chevron and summary, so a three-commit branch takes three rows. Branches merged into
  the trunk appear the same way, spanning from their merge commit. The trunk defaults to `origin/master` (or `origin/main`), can be changed with
  "Use as Trunk" in a branch's context menu, and never follows HEAD; checking out a branch expands
  its capsule instead. Trunk choice and expansion state are stored per repository.
* Show in graph rewrites the branch selection; Branches with pull requests turns on every branch
  with an open pull request (View › Show Branches With Pull Requests, ⇧⌘P), adding to the current
  selection unless show-all was on.
* Fetch (toolbar, or Repository › Fetch, ⇧⌘F) runs `git fetch --all --prune` and refreshes.
* Git and ssh run without a terminal, so anything they would ask there (a key passphrase, an
  HTTPS password, a new host key) comes up as a dialog from the bundled `askpass.sh`, and the
  ssh-agent socket is taken from launchd when the app was started without one in its environment.
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
  (dark) and `stark-light.json` (Stark Light by minhtrungcc from zed-themes.com, with its editor
  background removed so the diff pane keeps the system panel colour) and also reads
  `~/Library/Application Support/Lanes/Themes/*.json` and `~/.config/zed/themes/*.json`. Settings
  (⌘,) holds one theme for dark mode and one for light mode; whichever matches the app's current
  appearance is used, so a system that switches appearance on a schedule switches the colours with
  it. The built-in Lanes Dark / Lanes Light pair is listed too and is the fallback when a chosen
  theme file is missing. A theme's `syntax` map is looked up by scope with fallback (`keyword.return` → `keyword`);
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
* `LANES_DEBUG_SCRIPT=changes,history,sidebar-scroll,history-scroll` runs those steps a few seconds
  after launch and logs how long each took to lay out and draw (`snapshot` and `wait` are steps
  too). It is how mode switching and list scrolling were profiled.
