# iPhone Duo: facts and constraints for builders

What iOS 27.1 does with our app on iPhone Duo, and what the layouts in `DuoLayouts.html` assume.
Read this before touching a Duo layout.

## Sources

- Human Interface Guidelines, *Designing for iPhone Duo*
- Apple Developer documentation, *Preparing your app for iPhone Duo*
- Tech Talk 111462
- Tech Talk 111463, *Strike a pose with adaptive layouts on iPhone Duo*
- iOS 27.1 SDK (Xcode 27.1): `SwiftUICore.swiftinterface`, `UIHinge.h`, `UIHingeInteraction.h`
- Screenshots of this app on the folded Duo: `11-clean-tab0.png`, `11-clean-tab1.png`, `10-clean-settings.png`

## Poses

### Outer display, folded: 466×678 pt, compact width

- 1398×2034 px @3x. The spine is on the leading edge (corner radii 8 / 59).
- System chrome is a **full-height vertical strip on the trailing edge**, about 48 pt wide, centred at
  x ≈ 418. The content's trailing safe edge is about **382 pt**; the leading margin is about **20 pt**.
- The strip, from the top: camera corner and Dynamic Island, status (time over Wi-Fi/battery, the
  location arrow above when in use), the **toolbar items** as 48 pt icon-only circles in navigation
  order (Back/Close first, then the prominent action), and the **tab bar as a vertical capsule** at
  y ≈ 492–654.
- **Text-only toolbar buttons stay horizontal**, at the top trailing corner of the content
  ("Edit", "Find me!").

### Inner display, landscape, flat: 951×669 pt, regular width

- Controls **stay on the side**: the same vertical trailing strip. Not a sidebar, not a bottom bar.
- The fold at x = 475.5 is a `.division` reserved region, **inactive with zero width when flat**: there
  is no inset, but nothing important should sit across the centre (keep a gutter for partial opening).
- Use **even column counts**.
- In split views **only the detail column's bar goes vertical**; other columns keep horizontal bars.
  Inspectors keep horizontal bars.

### Inner display, portrait: 669×951 pt, regular width

- **Standard horizontal bars come back**: a navigation bar on top, the iOS tab bar at the bottom.
- The fold is horizontal at y = 475.5.
- Keep controls' relative positions across poses: "don't reinvent your app when it resizes",
  "move only what's necessary".

### Tabletop: inner portrait, partially open

- The fold is an active `.division` reserved region, **excluded from layout**.
- Glanceable content (read from a distance) goes in the **top** region, interactive controls in the
  **bottom** region. Scrolling lists stay put.

### Book: partially open, landscape

- Alerts and sheets move to the trailing side.
- Split views keep symmetric columns either side of the fold.

## Rules that apply everywhere

- **Full-bleed** is allowed for immersive, non-scrolling views (Wall), as long as nothing collides with
  the camera, the Dynamic Island or the status bar. Backgrounds may run under the strip; content stays
  inset.
- **No custom bars.** Use `TabView`, `NavigationSplitView` and `.toolbar` so the system can stand the
  bars up. A hand-made `HStack` of buttons does not move.
- **Every toolbar item has a title and an SF Symbol** (`Label` / `Button(_:systemImage:)`), so it can go
  vertical. Text-only items stay horizontal.
- **The hinge is for animation, not layout.** Layout follows size classes, `ArrangementView` and the
  reserved regions; reacting to every degree of `onHingeChange` makes layouts flicker.

## APIs (iOS 27.1, `@available(anyAppleOS 27.1, *)`)

| API | What it gives |
|---|---|
| `ArrangementView(primary:secondary:)` | Two related views placed by the system: `.split` puts them side by side when wider and stacked when taller (`.split.axes(.horizontal)` pins it), `.overlay` floats one over the other. Keep navigation around it; never put it inside a scroll view. |
| `GeometryProxy.reservedRegions(kind:options:)` | `[ReservedRegion]` with `frame`, `margins`, `isActive`. Kinds: `.division` (the fold), `.occlusion` (a camera). `options: .includeInactive` returns the flat fold too (zero width, but its position). |
| `@Environment(\.toolbarVerticalEdge)` | `HorizontalEdge?`: which edge the bars stand on, nil when horizontal. Only for custom controls that must follow the strip. |
| `.onHingeChange(isEnabled:) { old, new in }` | `DeviceHingeContext.hinge?` → `status` (`.closed`, `.partiallyOpen`, `.fullyOpen`) and `angle`. Called with the initial state, then on every change. |
| `UIHingeInteraction(updateHandler:)` | The UIKit equivalent (`UIHinge.status`, `angle`). |

## What the mockups assume (verify on hardware)

- The Dynamic Island is drawn as a 32×50 pt pill at the top of the outer strip (y 14–64): the
  screenshots leave that 0–75 pt gap empty but cannot show the hardware.
- The inner display's strip has no island; status at y ≈ 28, toolbar items from y ≈ 120. Where the inner
  camera's `.occlusion` region sits is unknown.
- The inner landscape strip uses the outer metrics: 48 pt wide, 84 pt trailing inset, the tab capsule
  162 pt tall and 24 pt above the bottom. Content's trailing safe edge is therefore 867 pt.
- The home indicator is drawn only in portrait.
- The 24 pt gutter around the fold (463.5–487.5) is our margin for partial opening, not a system value.
  In tabletop the active division is drawn 24 pt tall; read the real one from `reservedRegions`.
- Prominent toolbar items are amber glass because the app tints with `.tint(.amber)`. On the light
  ground, amber text ("Edit", "Find me!", the selected tab's label) is low contrast: that is the
  system drawing our tint, so the fix, if any, is a darker light-mode tint.

## Our layout decisions

- **Navigation**: four tabs (Near me, Journeys, Wall, Settings) are the only top-level navigation.
  Folded, Near me and Journeys carry a List | Lines and a List | Lanes switch at the top of their
  content; on the inner display both halves are side by side (Journeys list | Lanes, board | train,
  Near me list | line map) and the switch is hidden. Round trip is a toolbar item on a journey board.
  Entering tabletop selects the Wall tab once. No sidebar.
- Two-column screens split at the fold with `NavigationSplitView`, the leading column's width pinned to
  the division's position (`frame.midX` of the inactive region, or `width / 2`).
- The trailing column's content is 372 pt wide (495 → 867), within 10 pt of the folded content
  (362 pt), so one layout serves both.
- Round trip and tabletop Wall use `ArrangementView`; only the round-trip tie is placed by hand, at the
  division's frame.

## Checking a layout

`DuoLayouts.html` runs a check at load time and writes the result to `#crease-check`. It reports
any text inside the fold gutter (scrolling lists are counted apart, and allowed outside tabletop), any
non-chrome text past the strip's safe edge, and any text under system chrome.
