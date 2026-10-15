# Tableau, big screen — design handoff

The iOS app got the Tableau redesign; macOS is still a settings window. This handoff takes the same
system to every screen with room to spare: iPad, the Mac app, a two-pane "Duo" layout, a taller
widget, and the macOS menu bar.

The `.dc.html` files next to this one are the mockups: plain HTML with inline styles, so read them
for exact values (they need the canvas runtime to render; the source is the spec).
Canvas: https://claude.ai/code/artifact/3e5efba9-1370-4fe2-a620-1b4c18303aec

**Tokens, type and signature elements are unchanged**: see `Design/Tableau/HANDOFF.md` (colours,
JetBrains Mono, split-flap, route glyph, track rule, mode chip, hazard, time track). Everything below
is new, and reuses those pieces from `SNCFCore/Theme` instead of redefining them.

Sample data in every mockup: now is 17:40, the journey is Grenoble → Voiron (reverses at 13:00),
TER 17655 is +12, TER 17657 is cancelled, TER 17661 is +24, Grenoble → Chambéry has no service.

## Screens

| File | Screen | Platforms | Size drawn |
|---|---|---|---|
| `Main.dc.html` | **Station hall** — sidebar / journey board / train inspector | iPadOS, macOS | 1376×1032 |
| `Lanes.dc.html` | **Lanes** — every saved journey on one time axis (Timetable, light) | iPadOS, macOS | 1376×1032 |
| `Wall.dc.html` | **Wall mode** — full-screen departure board | iPadOS, macOS | 1376×1032 |
| `Duo.dc.html` | **Round trip** — outbound and way back side by side | two-pane width | 2 × 420×880 |
| `DuoWidget.dc.html` | **Extra tall widget** — vertical time track | widget | 364×800 |
| `MenuBar.dc.html` | **Menu bar extra** | macOS | popover 372 wide |

### Station hall (`Main.dc.html`)

`NavigationSplitView`, three columns, one code path for iPad and Mac.

- **Sidebar (280)**: app mark; "Go to station" search field (⌘K, station search already exists for
  the widget picker); NEAR ME row (radar glyph, nearest station, distance, next time); JOURNEYS
  (route glyph, name, direction rule in mono caps, next time in amber or a trouble badge: delay
  icon in caution, `NO SERVICE` pill in stop); VIEWS (Lanes ⌘2, Wall mode ⌘3, Round trip ⌘4);
  Settings; "Updated 17:40 · ⌘R" with the freshness dot.
- **Board (centre)**: route header (glyph, origin small, destination large title); segmented
  Board | Lanes; swap-direction and Wall-mode buttons; chips (DIRECT ONLY, REVERSES AT 13:00,
  "2 DISRUPTED TONIGHT" in caution); hero card = split-flap next time (46×66 tiles), NEXT TRAIN ·
  ARRIVES, mode chip + N° + duration, "in 2 min" in clear, **Remind me** button, then the **time
  track at full width** (spec in the Tableau handoff, scaled: 672 pt for 200 min, sleepers 4×20,
  hour sleepers 4×28, rails 10 pt apart, markers r 7–8). Then the board as a **table**: DEPART →
  ARRIVE | TRAIN | TIME ON BOARD (a duration bar, 100 pt = the longest trip) | STATUS. Selected row:
  amber 7 % fill + 1.5 pt amber ring. Footer: LAST TRAIN TONIGHT / FIRST TOMORROW, and the keyboard
  hint (↑↓ to pick, Space to pin).
- **Inspector (360)**: the selected train: N°, mode chip, headsign ("to Lyon Part-Dieu"); three
  stat tiles LEAVES / YOU ARRIVE / DELAY (the delay tile takes the status fill); track rule STOPS;
  the **stopping pattern** from `SNCFClient.trip(vehicleJourneyID:)`: your leg drawn solid in ink
  (hollow origin "YOU BOARD", amber destination "YOU GET OFF · 24 MIN"), the rest of the run dashed
  and at 50 %; amended times in the status colour with the timetabled one struck through underneath.
  Actions: **Watch train**, **Share ETA**, SNCF Connect link, disclaimer.

### Lanes (`Lanes.dc.html`)

Light / Timetable mode on purpose (it reads like a printed chart), follows the app's theme setting.

- Axis: a 4 h window, 4 pt/min in the mockup; hour labels; a NOW flag (amber fill, ink text).
- One card per saved journey: label column (route glyph, origin, destination, a mono summary line:
  "2 DISRUPTED · 25 MIN") and a track where **each train is a bar from departure to arrival**.
  Trains alternate between two sub-rows so consecutive bars never collide.
  - next: amber fill, 1.5 pt ink inset ring, NEXT label;
  - on time: ink fill, paper text;
  - delayed: status fill + status ring at the **expected** time, and a dashed "ghost" outline at the
    timetabled slot (struck time, 55 %), so the bar visibly slides;
  - cancelled: dashed stop outline, hatched fill, struck time, CANC.;
  - no service: the whole lane is hazard stripes with a black NO SERVICE plate and a count;
  - past (left of NOW): shaded.
- Hover / tap a bar: an ink popover (N°, delay pill, dep → arr, "was 18:12 · 3 stops · to …",
  Watch / Stops).
- Bottom: **service-day minimap** for the selected journey: trains per hour from 03:00 to 03:00
  (the `BoardState` service day), the visible window as a draggable amber-tinted brush.
- Range picker: NEXT 4 H / TONIGHT / TOMORROW AM.

### Wall mode (`Wall.dc.html`)

Full screen, screen kept awake, Esc / tap to leave. Ground `#0A0B0C` (a touch darker than the app).

- Header: DEPARTURES · PINNED STATION, station in 64 pt heavy; date in mono caps; a split-flap
  **clock** (52×74 tiles, ink digits — amber stays for train times).
- Board: every departure from the pinned station, each time as **four flap tiles** (25×38),
  destination 27 pt, "via …" from the stopping pattern, mode chip + N°, status. Cancelled rows:
  grey tiles without the split line, destination struck through.
- Right column: **LEAVE HOME IN** (amber card, two 62×88 flaps, "for the 17:46 to Grenoble.
  6 min walk to the platform."), then YOUR JOURNEYS cards (no-service one carries the hazard).
- Footer ticker: hazard block "INFO", the disruptions in one line, data credit + time + "Esc to leave".

### Round trip (`Duo.dc.html`)

A two-pane layout. There is no "Duo" iPhone today: build it as the layout used whenever the window
is wide enough for two compact columns (iPad, iPad split view, Mac), and it is ready for a foldable.

- Left pane ① OUTBOUND: the journey board; the picked train is ringed with a check.
  Bottom: THE WHOLE DAY OUT bar (train / time there / train back).
- Right pane ② WAY BACK: the reverse journey; **STAY AT LEAST** stepper (±15 min); returns that
  leave before arrival + stay are dimmed (TOO EARLY); the first that fits gets **FIRST THAT FITS**;
  later ones say how much longer you would stay ("+30 there"); the last one **LAST TRAIN**
  (amber outline). Primary button **Watch both trains** — if the return is cancelled or late, the
  next one that fits is proposed.
- A paper pill across the hinge pairs the arrival and the return (18:11 ··· 20:42).

### Extra tall widget (`DuoWidget.dc.html`)

Large-widget width, twice its height. Header (route), flap next time, then the **time track turned
vertical**: 17:40 at the top, 21:00 at the bottom, 2.6 pt/min; sleepers horizontal, rails vertical,
hour labels on the left; each departure written next to its marker (time → arrival, status pill,
"was 18:12 · TER 17655" for a delay). Footer: LAST 22:42 · Data © SNCF, freshness dot.
Dark and light are drawn; the light one uses an ink flap with amber digits.

### Menu bar extra (`MenuBar.dc.html`)

macOS `MenuBarExtra`, window style. Label: a small amber flap + "17:42 · 2′". Popover: journey
switcher (title + chevron), refresh; flap time + "in 2 min" + "TER 17653 · arr. 18:07"; compact time
track (324 pt); the next three trains; journey chips with a status dot; Open Trains near me ⌘O,
Wall mode on this display ⌘3, data credit.

## Features the designs introduce

| Feature | Where | Data |
|---|---|---|
| Stopping pattern in an inspector | Station hall | exists: `SNCFClient.trip(vehicleJourneyID:)`, already used by `BoardView` on iOS |
| Last train tonight / first tomorrow, disrupted count | Station hall, Lanes, widget | new: a service-day summary from `BoardState`'s 03:00 day |
| All journeys at once, with arrivals | Lanes, Wall, sidebar | new: concurrent fetch of every saved journey |
| Trains per hour over the service day | Lanes minimap | new: one day-long fetch per journey, cached per service day |
| Round trip pairing (stay, first fit, last train) | Round trip | new: pure logic + reverse-leg fetch from arrival + stay |
| Leave-by countdown (walking time) | Wall mode | new: per-station walk minutes (setting), optional MapKit walking ETA |
| Watch a train (reminder before it leaves, alert on delay change / cancellation) | Station hall, Lanes, Round trip | new: local notifications |
| Share ETA | Station hall | new: `ShareLink` text from the selected train and leg |
| Pinned station, keep the screen awake | Wall mode | new |
| Keyboard: ⌘K, ⌘R, ⌘1–4, ↑↓, Space, Esc | Station hall, Wall | new |
| Menu bar extra | macOS | new scene |

## Not in scope / open

- No platform ("voie") — same reason as in the Tableau handoff.
- "Extra tall" is not a WidgetKit family on iPhone or Mac today. Check the SDK; if none fits,
  keep the view (and its screenshot) ready and ship the vertical track where a family allows it.
- Copy stays in English.
