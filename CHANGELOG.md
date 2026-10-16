# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **The big screen**: the Tableau look taken to every surface with room to spare, built on frozen data contracts (with a mockup `.fake` behind previews, screenshots and tests), iPad support, an axis-parameterised time track (horizontal or vertical) and a shared app shell with ⌘K / ⌘R / ⌘1–4 / ↑↓ / Space / Esc.
- **Station hall** on iPad and Mac: a sidebar of saved journeys and the nearest station, a journey board with a split-flap next-train hero and the full-width time track, and an inspector that draws the selected train's stopping pattern (your leg solid, the rest dashed), with **Watch train** and **Share ETA**.
- **Lanes**: every saved journey on one time axis, each train a bar from departure to arrival (delays slide off a dashed ghost at the timetabled slot, cancellations hatched, a whole lane striped when nothing runs), a Watch / Stops popover, the service-day minimap and a NEXT 4 H / TONIGHT / TOMORROW AM range picker.
- **Wall mode**: a full-screen, always-dark departure board with a split-flap clock, a LEAVE HOME IN countdown, the saved journeys, a disruption ticker, and the display kept awake while it is shown. Picking a journey card puts that journey's trains on the board (arrival and trip time, its LEAVE HOME IN, its disruptions); the **Station** card shows every departure from the pinned station, or the nearest one. It opens on the last card picked (the first journey to begin with) and is an ordinary page: the sidebar stays and any view leaves it.
- **Round trip (Duo)**: the outbound board and the way back side by side, a minimum-stay stepper that re-tags the returns (TOO EARLY / FIRST THAT FITS / LAST TRAIN), the paper pairing pill across the hinge, and **Watch both trains**.
- **Extra-tall widget**: the time track turned vertical with a written label beside each marker, on the `.systemExtraLargePortrait` family where iOS / macOS 27 offers it.
- iPhone Duo: the app follows the system's vertical bars when folded, and opens a journey into board | train on the inner display.
- **A macOS menu-bar extra**: a window-style popover (journey switcher, next train, compact track, the next three trains, journey chips, Open / Wall-mode actions) and a bar label with the amber flap and the next time.
- **Live data behind all of it**: concurrent journey boards and a cached service-day summary, the round-trip planner, the leave-by countdown (per-station walk time, pinned station, optional MapKit walking ETA), watching a train (a reminder before it leaves and a delay-band / cancellation alert, re-evaluated in the foreground and in iOS background app refresh — never by spending the widget reload budget), and Share ETA.
- **Go to station** (⌘K) on the big screen searches every SNCF station, accents and case ignored, with ↑↓ / Return / Esc; a pick opens that station's departure board, which can be **pinned for Wall mode**.
- Station board: a line map, the station on the left and one lane per terminus flowing right, grouped by side of the line, with each train placed at its time.
- Tap a lane to open that journey without saving it, and add it to your journeys from there.
- On the station board's line map, a departing train fades its label, slides back to the station along its lane, and the next one takes its place.
- The station board and the Wall's station mode carry on into tomorrow late in the evening.
- **Saved journeys can be added, edited, reordered and deleted on the Mac and iPad**: a + in the sidebar's JOURNEYS header, Edit / Move / Delete on each journey, and a Journeys section in Settings.
- **Settings is a pane of the main window** on the big screen, in the Tableau style, with the same sections on the Mac's Settings window (⌘,).
- Split-flap times flip, tile by tile, when they change (off with Reduce Motion). A jump of more than one step
  spins the drum forward through every character in between, as a station board does when it changes journey;
  the Wall's LEAVE HOME IN minutes use the same tile.
- Wall mode keeps the LEAVE HOME IN card when a journey has no train left: its tiles spin to "--" and it says
  why, instead of disappearing and shifting the column.
- Late in the evening, journey views carry on into tomorrow: an end-of-service split, then the first trains of the next day.

### Fixed
- After the last train, a cancelled first train tomorrow no longer reads as "no service": the board shows the end of service and names the first train that runs.
- The station line map scrolls instead of squeezing a busy station's lanes, fits narrow screens, and its time labels open the train like its dots.

- Selected rows: a full-width amber tint with a bar on the left edge, instead of an inset ring that sat unevenly in the table.
- Big screen: NEAR ME shows the station nearest to you with its next departure and distance, or says why it cannot (location not allowed yet — with an **Allow location** button —, location off, no station within 20 km), falling back to the pinned station.
- Big screen: watching a train now schedules its reminder and measures delay changes from the moment you watch it, on the Mac and iPad too; a watch is dropped once its service day is over; a token typed after launch is used straight away; boards are no longer fetched twice per refresh.
- Big screen: the service-day summary (last train tonight, first tomorrow, the Lanes histogram) covers the whole 03:00-to-03:00 day instead of the next dozen trains; "N DISRUPTED TONIGHT" follows the live board.
- Big screen: the menu-bar label and Wall mode keep themselves current (departed trains drop off, a cancelled train is never "next"); the time track no longer draws a second amber dot at "now", its delay arcs bow as designed, and VoiceOver reads it as one sentence.
- Big screen: no amber text on paper in the light palette, the Lanes popover stays an ink card in both schemes, and the end-of-service board gets the widget's night treatment.
- Big screen: the appearance setting (System / Light / Dark) now applies everywhere, not only to the Settings pane: the sidebar, station hall, inspector, station board, round trip, the ⌘, window and the menu-bar popover follow it. On light, accent text turns to ink and the split-flap tiles to ink with amber digits; Wall mode, the Lanes ink popover and the NO SERVICE hazard stay dark by design. Switching back to System applies at once on macOS, without the window having to lose focus first.
- Big screen: ⌘1–4 (Station hall, Lanes, Wall mode, Round trip), ⌘K and ⌘R are real menu commands in the View menu (and the iPad keyboard overlay) instead of hidden buttons that did not always fire.
- Big screen: the Wall's clock and LEAVE HOME IN, and the station hall's "in N min", now advance at each minute change on their own instead of only on a reload.
- Lanes draws every train of the service day its minimap counts, not only the next dozen.
- Journey boards show each train's stopping pattern again (the vehicle journey is now read from the journey sections).
- The iOS upload to App Store Connect was rejected for declaring no `UISupportedInterfaceOrientations`; the app is now iPhone-only and portrait-only, so it no longer claims iPad support.
- Version and build number now come from `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` instead of a hard-coded 1.0 (1), which App Store Connect would have rejected on a second upload; declares no non-exempt encryption so TestFlight skips the export-compliance prompt.

## [1.2.0] - 2026-10-14

### Added
- The **large widget** now lists more departures and closes with a **time track**: the trains it lists drawn as dots along a length of rail at the time each one leaves — the soonest in amber, a delay sliding its dot to the amended time with a dashed arc back to the scheduled one, a cancellation crossed out — then the SNCF attribution. Instead of being the medium widget with extra rows and empty space.
- **An app on iOS**, instead of a window that only held the token. Three tabs: **Near me**, the radar board full-screen; **Journeys**, every saved journey at once; and **Settings**, the former window. macOS is unchanged — the widgets are still the product there.
- Each saved journey is a card carrying its next departures as tiles that slide sideways, and an icon on its title as soon as something is wrong with it: a cancellation, a delay, the end of the service, or data that could not be fetched. The title names the leg actually being shown, so an automatic journey past its switch time reads the way it runs; one that departs from the nearest station names its pair with a two-way arrow instead, because it has no fixed departure to name.
- Both screens refresh themselves — a minute's tick drops the trains that have left, and the boards are fetched again once the delays go stale — say when they were last updated, and pull to refresh when you would rather not wait.
- Near me carries the radar symbol next to its title, and the dish sweeps while a position is being found.
- **Find me!** on Near me, which refuses the system's cached fix and waits for a live one. Everything else takes whatever position the system already has, which is right for a screen that reloads on its own and wrong for someone who has just got off a train.
- Saved journeys are stored in the App Group, so the Trip widget's station picker now suggests their stations instead of offering nothing until you type.
- **A split-flap look**, "Tableau", across the iOS app and both widgets: a departure-board palette in JetBrains Mono, with flap tiles for the next time, a route drawn as pins on a line, delays and cancellations carried by a station-board colour code, and hazard stripes under the NO SERVICE state. The theme — colours, font and the shared pieces — lives in `SNCFCore` so the app and the widget read one source and never drift apart. The widgets follow the system light or dark setting, as a widget must.
- **Light / Dark / System** picker in Settings on iOS. Every colour has a light and a dark value, and the whole app switches as one — the two are never mixed on screen. The widgets cannot be forced per-app, so they keep following the system.
- **Managing saved journeys**: an Edit button on Journeys collapses the cards to a plain list, where a journey swipes away to delete and taps to open its configuration pre-filled. The same journey screen now both creates and edits, replacing the one you changed in place.

### Fixed
- The Lock Screen complications showed "Please adopt containerBackground API" instead of a board: the accessory views never called `.containerBackground`, which iOS 17+ requires of every widget. Error states there also spelled out the full sentence, which the complication clipped unreadably — each error now has a terse two-word form that fits.
- Signing for an iPhone failed with a paid team: the App Group was spelled `$(TeamIdentifierPrefix)$(BUNDLE_ID_PREFIX)`, which is the macOS shape. That variable only exists at signing time, and a paid team makes Xcode register the group on the developer portal, which rejects it — taking provisioning profile creation down with it. `SNCF_APP_GROUP` now resolves to the team prefix on macOS and to `group.<bundle prefix>` on iOS, which is the shape iOS requires.

### Changed
- The token can be typed in the app on iOS too, wherever an App Group exists. The compiled-in `SNCF_TOKEN` stays the fallback for free Apple accounts, which get no App Group there.

## [1.1.0] - 2026-10-12

### Added
- **Radar widget**: the next departures from the station closest to you, in every direction, with no configuration. It finds that station through the SNCF `places_nearby` endpoint, from a position rounded to about 100 m.
- **iOS 18 support**: the same app and widgets build for iPhone and iPad, including the Lock Screen (rectangular and circular) sizes. On iOS the token comes from `SNCF_TOKEN` in `Config/Local.xcconfig`, because a free Apple account cannot share an App Group there.
- A refresh button in each widget's header, which fetches immediately instead of waiting for the system's next reload. It redraws the widget's last board, faded and labelled "Updating…", while the new one is on its way, and only ever refreshes the widget it was clicked on.
- Medium and large widgets name the service of each train — TER, TGV, OUIGO, Intercités, or Car when a coach replaces it.
- CI on GitHub Actions: unit tests and an unsigned build of the app and widget, for macOS and iOS.
- `scripts/render-screenshots.sh` regenerates the README, guide and social images from the real widget views.
- Issue and pull request templates, contributing guide.

### Changed
- The widget is now a bundle of two widgets, **Trip** (the former journey widget, same identifier and settings) and **Radar**.
- Reloads are asked for 5 min before the next train instead of every 15 min, bounded by a 20-minute floor and a 60-minute ceiling, with a single reload booked for the night. The daily WidgetKit budget is spent when a delay can actually appear.
- Each fetch covers hours: 12 journeys for Trip, 20 departures for Radar.
- Trains stay listed after the 30-minute mark instead of being replaced by "Data out of date"; the timestamp turns orange to say the delays are old. The timeline now holds an entry for every train fetched, so one fetch keeps the widget right for the whole evening.
- Privacy wording: a position now leaves the device in Radar mode only, rounded to about 100 m.

### Fixed
- The widget never got a position. Reading `CLLocationManager().authorizationStatus` off a throwaway manager answers `.notDetermined` until locationd replies, so an authorized widget decided it had no permission and gave up without asking. There is now one long-lived location client per process, the status is kept by its delegate, and a fix is attempted whatever the status says — it only names the failure.
- Asking for the permission is not asking for a position either, so the system often had nothing cached and the widget's attempt started from cold. The host app now takes a fix at launch and shows what it found, and the widget waits up to 12 s, falling back to an older fix rather than to nothing.
- On the small widget a row with a delay badge wrapped onto two lines; the middle column now shrinks instead.

## [1.0.0] - 2026-10-08

### Added
- macOS widget (small, medium, large) showing the next direct trains between two stations, from the official SNCF API.
- Real-time delays in bands (0–10, 11–19, 20+ min) and cancelled trains.
- Widget-wide states:
  - **NO SERVICE** on hazard stripes when every remaining train is cancelled;
  - **End of service** with the next day's first train;
  - data unavailable, with the reason;
  - out of date after 30 minutes.
- Direction: fixed, reversed, or automatic at a configurable switch time (13:00 by default).
- Optional nearest-station mode using Core Location, on-device only.
- Host app to store the API token and request location permission.
- `scripts/install.sh` to build and install with a free Apple account, and a step-by-step install guide.

[Unreleased]: https://github.com/Wonskcalb/trains-near-me/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/Wonskcalb/trains-near-me/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Wonskcalb/trains-near-me/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Wonskcalb/trains-near-me/releases/tag/v1.0.0
