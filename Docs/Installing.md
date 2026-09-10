# Installing

Builds are published to [GitHub Releases](https://github.com/Lermex/Lanes/releases). Unzip and
move `Lanes.app` to Applications. Requires macOS 26.

Releases are signed with a Developer ID and notarized, so they open without a security prompt.
Releases that were only ad-hoc signed (v0.1.5 and earlier) need the quarantine flag cleared once:

```sh
xattr -dr com.apple.quarantine /Applications/Lanes.app
```

## Updates

The app updates itself with [Sparkle](https://sparkle-project.org): it checks
`https://github.com/Lermex/Lanes/releases/latest/download/appcast.xml` once a day and on
Lanes › Check for Updates…, and installs the zip from the release after verifying its EdDSA
signature and that it was signed by the same Developer ID. Releases up to v0.1.6 have no updater,
so the first self-updating build has to be downloaded by hand.

`LANES_UPDATE_FEED=<url>` points a build at another appcast for trying updates locally.
