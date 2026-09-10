# Debugging

* Setting `LANES_DEBUG=1` prints a state summary to stderr after each refresh.
* Setting `LANES_SNAPSHOT_DIR=<dir>` adds a Debug › Snapshot Window command (⇧⌘D) that writes the
  window as a PNG there without needing Screen Recording permission (glass and sidebar vibrancy
  render blank in it). The driver's `screenshot` step writes the window as the window server
  composes it instead, glass and shadow included, which is how the README's hero image is made.
* `LANES_DEBUG_SCRIPT=<steps>` runs a comma-separated list of steps a few seconds after launch and
  logs how long each took to lay out and draw. It is how mode switching and list scrolling were
  profiled, and how the app is checked without accessibility access. Steps: `changes`, `history`,
  `sidebar-scroll`, `history-scroll`, `wait`, `snapshot`, `screenshot`, `snapshot-sidebar`,
  `sidebar-window`, `settings`, `snapshot-settings`, `light`, `dark`, `trunk-on`, `trunk-off`,
  `collapse-all`, `expand:<name>`, `reveal:<name>`, `select-path:<path>`, `select-stash`,
  `check-updates`, `git-env`, `shrink`, `minsize`, `fit-min`, `splits`, `constraints`,
  `measure-views`.

  ```sh
  LANES_DEBUG=1 LANES_SNAPSHOT_DIR=/tmp/snaps LANES_DEBUG_SCRIPT=dark,trunk-on,collapse-all,wait,screenshot \
    Build/Lanes.app/Contents/MacOS/Lanes --repo=/path/to/repo
  ```
* Quit the app normally rather than killing it: after a kill, macOS treats the next launch as a
  resume and SwiftUI restores windows instead of opening the default one.
* Do not launch the app with a bare path argument; AppKit treats it as a document to open and
  SwiftUI then never opens the main window. Use `--repo=<path>` (what `make run` does).
