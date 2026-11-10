# Debug screen

A page inside the settings sheet that shows what the app, the ads and the
notifications are doing on this phone, with buttons to try them. Code:
`game/ui/widgets/debug_page.gd` (`DebugPage`), opened by `SettingsSheet`.

## Opening it

- Any build, also TestFlight and release: Home > Settings, then tap the word
  **Settings** seven times.
- Developer mode (editor and debug builds): a **Debug** row under Credits.

Nothing on it gives coins, points or revives, so it is safe in a release
build. Only developer mode shows "Give free revives back".

## What it shows

Rows refresh twice a second.

| Section | Rows |
|---|---|
| App | version and build type, gameplay version, engine, device and OS, screen and safe area, language, frames per second, the day, best score |
| Ads | which ad service runs, test or real ad unit, consent status and form, whether the SDK started, whether an ad is loaded, loads asked and loaded, the last load error, how the last ad ended, free revives left |
| Notifications | whether push is in the build, whether a server is set up, the token (its ends and length only), the clock offset, the last error, Board alerts on or off, whether permission was asked |

The ad and push rows come from `AdsService.debug_rows()` and
`PushService.debug_rows()`; a new service fills in its own.

## Buttons

- **Copy everything**: the whole report as text on the clipboard.
- **Google test ads** (switch): asks for Google's test ads instead of the real
  unit. Saved in the profile (`test_ads`), so it survives a restart. Use it in
  TestFlight builds: real ads are rare before the app is in a store.
- **Load an ad**, **Show the ad**: the rewarded ad without playing a run.
- **Ad choices**: Google's privacy form.
- **Use up free revives**: the next crash then offers the ad.
- **Send a test notification**: asks the server (`send_test_push`,
  `supabase/migrations/20261110130000_test_push.sql`) to send one to this
  phone along the same path as a Board alert. Leave the app right after
  tapping: iOS does not show a notification while the app is open. At most one
  per 30 seconds.
- **Ask for permission**, **Fetch the token**: the two steps the game normally
  takes when the player first holds a prize spot.

## Tests

`tests/unit/test_debug_page.gd` (the page) and
`supabase/tests/40_test_test_push.sql` (the server function; `tools/db_test.ps1`).
