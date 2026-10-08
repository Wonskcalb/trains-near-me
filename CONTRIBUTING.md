# Contributing

Thanks for helping! Bug reports, ideas and pull requests are welcome.

## Getting started

1. Follow steps 1–3 of the [install guide](GUIDE.md) (Xcode, Apple Account, SNCF token).
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team. That file is git-ignored.
3. Open `TrainsNearMe.xcodeproj` and run the `TrainsNearMe` scheme.

## Where things live

- **`SNCFCore/`**: everything testable without WidgetKit, including the API client and parser, the journey and direction logic, the service-day rules and the refresh plan. New logic goes here, with a test.
- **`Widget/`** and **`App/`**: thin SwiftUI and WidgetKit layers on top of the core.
- **`project.yml`**: the source of truth for the Xcode project. After editing it, run `xcodegen generate` and commit the regenerated `TrainsNearMe.xcodeproj`.

## Before opening a pull request

- Run the tests: `swift test --package-path SNCFCore`. They never call the live API; add a fixture under `SNCFCore/Tests/SNCFCoreTests/Fixtures` instead.
- If you changed how the widget looks, regenerate the images: `sh scripts/render-screenshots.sh`.
- If you changed the widget's name, description or sizes, bump `CURRENT_PROJECT_VERSION` in `project.yml`. Otherwise macOS keeps showing the cached widget.
- Add a line to `CHANGELOG.md` under *Unreleased*.
- Keep everything in English: code, comments, docs and commit messages.

Never commit an SNCF token or your `Config/Local.xcconfig`.
