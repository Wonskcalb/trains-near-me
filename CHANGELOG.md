# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Radar widget**: the next departures from the station closest to you, in every direction, with no configuration. It finds that station through the SNCF `places_nearby` endpoint, from a position rounded to about 100 m.
- **iOS 18 support**: the same app and widgets build for iPhone and iPad, including the Lock Screen (rectangular and circular) sizes. On iOS the token comes from `SNCF_TOKEN` in `Config/Local.xcconfig`, because a free Apple account cannot share an App Group there.
- CI on GitHub Actions: unit tests and an unsigned build of the app and widget.
- `scripts/render-screenshots.sh` regenerates the README, guide and social images from the real widget views.
- Issue and pull request templates, contributing guide.

### Changed
- The widget is now a bundle of two widgets, **Trip** (the former journey widget, same identifier and settings) and **Radar**.
- Privacy wording: a position now leaves the device in Radar mode only, rounded to about 100 m.

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

[Unreleased]: https://github.com/Wonskcalb/trains-near-me/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Wonskcalb/trains-near-me/releases/tag/v1.0.0
