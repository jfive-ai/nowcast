# Nowcast visual identity

Nowcast turns many streams into one brief. The proposed **Signal** identity shows three quiet input lines converging, followed by a single highlighted result. Its simple silhouette is retained in the monochrome menu-bar glyph.

## Three directions for review

These are original vector concepts. Signal is integrated as the proposed final direction; the alternatives remain editable for design review in the pull request.

| Signal — proposed | Briefing | Focus |
| --- | --- | --- |
| ![Three streams converge into a single signal](../design/signal.png) | ![A short editorial list with a highlighted item](../design/briefing.png) | ![An open lens around a focused point](../design/focus.png) |
| Best expresses synthesis across sources; a distinct silhouette at small sizes. | Familiar editorial metaphor, with less emphasis on synthesis. | Calm attention metaphor, with less connection to a briefing. |

## Color and typography

- Deep teal `#163F42`: app-icon surface; quiet enough to sit in the Dock.
- Warm paper `#F6F5ED`: primary icon strokes.
- Soft mint `#AFE6CA`: the selected signal. Its circular shape also distinguishes it without color.
- The app continues to use the native system font and semantic SwiftUI text styles. These icon colors do not replace dynamic system colors in app controls or report text.

The same app icon works against light and dark desktops. The menu asset has a transparent background and uses template rendering, allowing macOS to provide the appropriate foreground in light, dark, selected, and increased-contrast menu bars. The previews below show the intended light/dark treatment, enlarged for inspection:

![Dark glyph on a light menu](../design/menu-light.png) ![Light glyph on a dark menu](../design/menu-dark.png)

## Source and reproduction

The authoritative editable vector program is [`design/render-icons.swift`](../design/render-icons.swift). It emits both SVG masters and raster assets from the same geometry; edit this source, then run from the repository root:

```sh
swift design/render-icons.swift
xcodegen generate
```

No downloaded art, fonts, or third-party renderer is required. The SVGs under `design/` can also be opened in a vector editor; port edits back into the drawing program before regenerating to keep every size consistent.

The macOS `AppIcon.appiconset` contains the ten standard 16, 32, 128, 256, and 512 point slots at 1x and 2x (16 through 1024 physical pixels, including 64). The menu glyph is an 18-point transparent image at 1x and 2x. The existing recursive resource entry includes the asset catalog; no duplicate resource entry is needed.

The rendered concepts, all app-icon pixel sizes, and menu glyph at native size are checked before publication. Design selection is reviewable in the PR; live Dock/Finder appearance may require macOS to refresh its cached icon after installing a new build.
