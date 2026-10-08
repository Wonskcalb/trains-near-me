# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- CI on GitHub Actions: unit tests and an unsigned build of the app and widget.
- `scripts/render-screenshots.sh` regenerates the README, guide and social images from the real widget views.
- Issue and pull request templates, contributing guide.

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
