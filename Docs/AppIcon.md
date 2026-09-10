# App icon

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
