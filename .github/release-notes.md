**Install:** unzip, move `Lanes.app` to Applications. The build is ad-hoc signed, so macOS blocks
the first launch; either right-click › Open, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Lanes.app
```

Requires macOS 26.
