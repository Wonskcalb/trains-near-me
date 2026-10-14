# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **An app on iOS**, instead of a window that only held the token. Three tabs: **Near me**, the radar board full-screen; **Journeys**, every saved journey at once; and **Settings**, the former window. macOS is unchanged — the widgets are still the product there.
- Each saved journey is a card carrying its next departures as tiles that slide sideways, and an icon on its title as soon as something is wrong with it: a cancellation, a delay, the end of the service, or data that could not be fetched. The title names the leg actually being shown, so an automatic journey past its switch time reads the way it runs; one that departs from the nearest station names its pair with a two-way arrow instead, because it has no fixed departure to name.
- Both screens refresh themselves — a minute's tick drops the trains that have left, and the boards are fetched again once the delays go stale — say when they were last updated, and pull to refresh when you would rather not wait.
- Near me carries the radar symbol next to its title, and the dish sweeps while a position is being found.
- **Find me!** on Near me, which refuses the system's cached fix and waits for a live one. Everything else takes whatever position the system already has, which is right for a screen that reloads on its own and wrong for someone who has just got off a train.
- Saved journeys are stored in the App Group, so the Trip widget's station picker now suggests their stations instead of offering nothing until you type.

### Fixed
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

[Unreleased]: https://github.com/Wonskcalb/trains-near-me/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Wonskcalb/trains-near-me/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Wonskcalb/trains-near-me/releases/tag/v1.0.0
