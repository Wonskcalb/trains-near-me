# Privacy policy — Trains near me

_Last updated: 25 November 2026_

Trains near me has no account, no analytics, no advertising and no server of its own. Nothing is
collected by the developer.

## What leaves your device, and where it goes

The app and its widgets talk to one service only: the SNCF open data API (`api.sncf.com`), run by SNCF.

- **Your SNCF API key** is sent with every request, as SNCF requires, to identify your own free quota.
- **Your position**, only when Radar or "Depart from nearest station" needs it, rounded to about
  100 m (three decimals of latitude and longitude), to find the station closest to you. Your exact
  position never leaves the device.
- **The stations you ask about**, to fetch their departures.

What SNCF does with those requests is covered by the SNCF API terms and privacy policy.

## What stays on your device

Your API key, your saved journeys, your appearance setting and the last departures fetched by each
widget are stored on the device, shared only between the app and its widgets. Deleting the app
deletes them.

## Location permission

Location is optional. Without it, Radar cannot find a station and saved journeys run in the order
you set. You can change the permission at any time in the iOS or macOS Settings.

## Contact

Questions: open an issue at <https://github.com/Wonskcalb/trains-near-me/issues>.
