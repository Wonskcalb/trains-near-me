# Tableau — design handoff

UI redesign for Trains near me. The `.dc.html` files next to this one are the mockups (plain HTML with inline styles: read them for exact values). Canvas: https://claude.ai/code/artifact/09805edb-3f12-4277-b910-be763a315d0a

Two modes:
- **Board** (dark): a station departure board. Black ground, times in amber.
- **Timetable** (light): a printed timetable leaflet. Warm paper, black ink, amber only as a fill (never as text on light).

## Tokens

| Token | Dark (Board) | Light (Timetable) |
|---|---|---|
| ground | `#0E0F11` | `#F2EFE8` |
| surface / card | `#17191C` | `#FBFAF7` |
| raised / flap / tile | `#23262B` | `#ECE8DF` |
| ink | `#F2EFE8` | `#16171A` |
| ink.2 (secondary) | `#8F8D86` | `#66645E` |
| amber (accent) | `#FFC23D` | `#FFC23D` (fill only) |
| clear (leaving soon) | `#46C27A` | `#2B7F4C` |
| caution (delay 11–19, unknown) | `#FF9A55` on `rgba(255,138,61,.16)` | `#9A4808` on `#FBE3CC` / `#F2DFC6` |
| stop (≥20, cancelled) | `#FF6B5F` on `rgba(255,90,78,.16)` | `#A3231A` on `#F8D9D4` / `#F1D5CF` |

Status thresholds are unchanged (`DepartureStatus`). Asset catalog colours with Any/Dark variants are the natural home.

## Type

- **JetBrains Mono** (bundle the font): times, train numbers (`N° 17654`), delays, mode chips, small caps labels (letter-spacing ~1.3).
- **SF Pro** (system): station names, titles, prose. Large titles stay native.

## Signature elements

- **Split-flap time**: only the next train on Near me. 4 tiles (36×52, radius 7, `#23262B`, amber digit), a 1px ground-coloured line across the middle.
- **Route glyph**: hollow origin dot, line, solid destination dot. Same as `JourneyPins` in the widget; the destination dot gets the amber accent.
- **Track rule** (section divider): sleepers 4px wide every 13px, wider than the rails (`#3A3631`); two 2px rails (`#9C9A93`) inset 3px from the top and bottom.
- **Mode chip**: outlined (1px, ~20% ink), radius 5, mono 10.5 semibold.
- **Hazard (NO SERVICE)**: diagonal stripes -45°, amber/ground. In the app: full-bleed band at the top, black plate "NO SERVICE". In widgets: amber at 34% with a radial fade (full in the centre, ~20% at the edges) so the titles stay readable. Only when nothing runs (`.noService`), never for a single cancelled train.
- **End of service**: keep the existing navy gradient and moon; first train time in amber mono.

## Screens

- `Main.dc.html`: Near me (dark). Toolbar "Find me!" as a glass capsule; nearest station card with the flap time; track rule "THEN"; board list (time / destination + mode + number / status pill or "23 min").
- `Board.dc.html`: Journey board. Route header (glyph, origin small, destination large title), chips (DIRECT ONLY, REVERSES AT 13:00), rows departure → arrival with dashed connector, "NEXT" tag, "leaves 18:24" under delays. Button "Tickets & details in SNCF Connect" + disclaimer.
- `NoService.dc.html`: all trains cancelled for a journey.
- `Journeys.dc.html`: light. Cards with the route glyph and the direction rule in mono caps (REVERSES 13:00 / ALWAYS THIS WAY / FOLLOWS YOU), trouble icon next to the destination, horizontal tiles.
- `Settings.dc.html`: existing sections + "Tickets & full timetables" (SNCF Connect link) + About (source, licence, disclaimer).
- `Widgets.dc.html`: same layout as today, Tableau type and colours, light/dark/states, lock screen.
- `Icons.dc.html`: app icon candidates (A Flap is the base) and the glyph set. Tab bar: radar / route glyph (replaces the star) / sliders (replaces the gear).

Tab bar: floating glass capsule (iOS 26 style); with SwiftUI's native `TabView` on iOS 26 you get it for free, so only tint it.

## Disclaimers & redirect

- Text: "Not affiliated with SNCF. Train data © SNCF, via the SNCF open data API."
- Links to `https://www.sncf-connect.com` (text only, no SNCF logo).
- Places: Board footer, NoService (amber primary button), Settings › About, large widget footer.

## Not in scope / open

- Platform ("voie"): the SNCF API stop points are per mode (`stop_point:SNCF:…:Train`), no platform in the fixtures. A dashed "VOIE —" slot exists in `System.dc.html` only if a source turns up; don't add it to screens.
- App icon: final pick between A / B / C still open.
- Copy stays in English, as in the app today.

## Time track (large widget footer)

The rail at the bottom of the large widget is a time axis, not decoration. Source of truth: the `<svg>` just before "Data © SNCF" in `Widgets.dc.html`. Spec, so nothing has to be reverse-engineered:

- **Range**: from `entry.date` (now) to now + 200 min. x = minutes since now × (width / 200). Mockup: 336 pt wide, 17:40 → 21:00, 1.68 pt/min.
- **Sleepers** (drawn first): one every 10 min, 3 pt wide, rounded 1. Regular: 14 pt tall, `#E2DDD2` light / `#3A3631` dark. On the hour: 18 pt tall, `#C9C2B4` light / `#4A453E` dark.
- **Rails**: two 1.6 pt lines across the full width, 7.4 pt apart, centred on the sleepers, `#A9A69E` light / `#9C9A93` dark. Sleepers stick out 3 pt above and below the rails.
- **Hour labels**: under the hour sleepers, JetBrains Mono 9 medium, ink.2. The last one at the right edge is right-aligned ("21h").
- **Markers** (drawn last, centred on the track, one per upcoming departure, positioned at `expectedDeparture`):
  - next train: r 5.5, amber `#FFC23D` fill, 2 pt ink stroke;
  - on time: r 5, ink fill;
  - delayed 11–19 (or unknown): r 5, `#D9771A`; severely delayed: r 5, `#C42B1C`;
  - delayed trains also get a "ghost" at `scheduledDeparture`: r 3.2, card-colour fill, 1.3 pt stroke in the status colour (`#9A4808` / `#A3231A`), joined to the real marker by a dashed (2/2) quadratic arc 1.3 pt above the track, peaking ~10 pt up;
  - cancelled: r 4.6 hollow (card fill, `#A3231A` 1.6 pt stroke) with an × inside, at `scheduledDeparture`.
- Departures beyond the range are not drawn. Height: 46 pt including labels.
- Accessibility: one label for the whole track listing the departures (see the svg's `aria-label`).
- SwiftUI: a single `Canvas`, fed by `entry.upcoming`.
