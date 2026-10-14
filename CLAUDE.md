# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift test --package-path SNCFCore            # the whole suite (no network: everything is fixtures)
swift test --package-path SNCFCore --filter Parsing          # one suite
swift test --package-path SNCFCore --filter "Parsing/onlyDirectTrainsServingTheJourney"   # one test

xcodegen generate                             # regenerate the .xcodeproj after editing project.yml
sh scripts/install.sh                         # Release build + install into /Applications (macOS)
sh scripts/render-screenshots.sh              # re-render Design/*.png from the real widget views

# What CI runs, and the only way to compile-check app + widget without a signing team:
xcodebuild -project TrainsNearMe.xcodeproj -scheme TrainsNearMe -configuration Release \
  -destination "generic/platform=macOS" DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=NO build
# same with -destination "generic/platform=iOS Simulator"
```

Pass `-derivedDataPath build` when building by hand: `xcodebuild` registers its product with
LaunchServices, and a DerivedData copy competes with the installed app for which widget macOS loads.

Swift 6 language mode, strict concurrency. No third-party dependencies — keep it that way.

## Architecture

Two WidgetKit widgets (**Trip**: next direct trains for one configured journey; **Radar**: departures
from the station closest to you) plus a host app. One scheme, two platforms: macOS 15+ (app is a
settings window) and iOS 18+ (app is a three-tab UI).

```
SNCFCore/   Swift package. All logic that can be tested without WidgetKit. New logic goes here, with a test.
Widget/     WidgetBundle, two AppIntentTimelineProviders, SwiftUI views, App Intents configuration.
App/        SettingsView (both platforms) + iOS-only RootView/BoardView/JourneysView, all `#if os(iOS)`.
Config/     Base.xcconfig; Local.xcconfig is git-ignored and holds DEVELOPMENT_TEAM, BUNDLE_ID_PREFIX, SNCF_TOKEN.
```

Data flow: `SNCFClient` (4 Navitia endpoints) → `NavitiaParser` → `[TrainDeparture]` →
`BoardState.from(_:now:)` → a `DeparturesEntry` timeline from `RefreshPlanner` → SwiftUI.

Key pieces in `SNCFCore`:

- **`BoardState`** is where "what does the widget show" is decided: departures, `endOfService`,
  `noTrains`, `noService` (every remaining train cancelled), `unavailable(TrainServiceError)`.
  Its **service day** starts at 03:00, so a 00:15 train still belongs to the previous evening.
- **`RefreshPlanner`** exists because WidgetKit grants ~40–70 reloads per widget per day. Reloads are
  asked for 5 min before the next departure, floored at `minimumGap` (20 min, the budget knob) and
  capped at an hour; after the last train, one reload before tomorrow's first instead of polling all
  night. `entryDates` puts an entry just after each train leaves so departed trains drop off without a
  reload, plus one at +30 min (`staleAfter`) that turns the timestamp orange.
- **`JourneySelector.leg`** resolves a `JourneyConfiguration` to a direction: nearest-station mode wins
  when a location is known (compared on-device, ties go to A), otherwise forward/reverse/automatic-at-
  `switchMinute`.
- **`SharedSettings`** is the App Group bridge: token, saved journeys, per-widget cached board, and the
  refresh handshake. Everything degrades to nil/no-op when there is no App Group (`isShared == false`),
  which is the free-Apple-account-on-iOS case.
- **`LocationFix.shared`** must stay a long-lived singleton: a fresh `CLLocationManager` reports
  `.notDetermined` until locationd replies, so a throwaway manager makes an authorized process believe
  it has no permission. A fix is always attempted; the status only names the failure.

## Things that will bite

- **`data_freshness=base_schedule`, never `realtime`.** With `realtime` cancelled trains vanish from
  the response; with `base_schedule` every scheduled trip is returned and real-time changes arrive as
  linked disruptions, which is what makes CANCELLED rows and delays possible from a single request.
- **The App Group id is shaped per platform** in `project.yml`: `$(TeamIdentifierPrefix)…` on macOS,
  `group.…` on iOS. `$(TeamIdentifierPrefix)` only exists at signing time and iOS rejects it when
  registering the group on the portal. Both targets must share one team or the widget cannot read the token.
- **`ENABLE_DEBUG_DYLIB: NO`** must stay. The App Intents runtime looks the configuration intent up in
  the main executable; with the debug dylib the widget loses its "Edit" option (`ActionNotFound`).
- **`project.yml` is the source of truth.** Xcode's own project edits are overwritten by
  `xcodegen generate`; commit the regenerated `.xcodeproj`. Signing settings belong in `Local.xcconfig`.
- **A widget's refresh button** is `Button(intent:)` → `RefreshIntent` → `WidgetCenter.reloadAllTimelines()`.
  The "updating" state comes from `SharedSettings.requestRefresh`/`takeRefreshRequest`, keyed by widget
  kind + signature so one widget never puts another in that state.
- **`Station` is packed into a single App Intents entity id** (`entityIdentifier`, `id|lat|lon|name`),
  because widget configuration only persists identifiers and resolving one must not cost a request.
- **`scripts/render-screenshots.sh` rewrites a copy of `Widget/DeparturesWidget.swift`** with `sed`
  (drops `@main`, makes `widgetFamily` a parameter, swaps `containerBackground` for a background). It
  asserts its substitutions landed, so renaming those lines breaks the script — fix the `sed` there.

## Conventions

- English everywhere: code, comments, docs, commit messages.
- Comments explain *why* (an Apple constraint, an API quirk, a budget trade-off), not what the code does.
  Match that: the existing comments are the house style.
- Tests use swift-testing (`@Suite`/`@Test`/`#expect`) with a fixed `Europe/Paris` calendar and the
  `at(hour, minute)` helper. New API behaviour gets a fixture in `SNCFCore/Tests/SNCFCoreTests/Fixtures`,
  never a live call.
- Add a line to `CHANGELOG.md` under *Unreleased*. Bump `CURRENT_PROJECT_VERSION` in `project.yml` when a
  widget's name, description or sizes change, or macOS keeps showing the cached widget.
- Never commit a token or `Config/Local.xcconfig`.
