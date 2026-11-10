# Revive

Status: built, but real ads have never run on a phone. The sim, replay and
checker, the offer with free revives, the migration file, the heart on the
boards, the AdMob plugin and its provider with the consent form are in. Still
to do by hand: deploy the migration, and test an Android and an iOS build on a
phone (see "AdMob" below). Mockup:
https://claude.ai/artifact/BbTtTcBhVminhmBNc2fceH

## Decisions so far

- One revive per run. Three free revives a day, then a rewarded ad.
- The Revive Pass (one-time purchase, €4.99, see "Revive Pass" below) makes
  every revive offer free: no ad, no daily limit. Still one revive per run.
- Revived runs count on the verified boards and carry a small heart mark.
- No countdown on the offer. No ad available and no free revive left: no offer,
  straight to game over.
- The sim does not know why a revive happened (free or ad). It only sees
  "revive at tick N".
- No offer below 5 points (`Main.REVIVE_MIN_SCORE`): a quick crash still
  restarts with one tap.
- Closing the ad early counts as Skip: the run ends. An ad that fails to show
  after the player asked for it revives anyway.
- After a revive the run waits, paused, for a tap.

## Revive Pass

The only ads in the game are the optional rewarded revive ads; the pass
removes them.

- Product `revive_pass` (`DiamondPacks.REVIVE_PASS`), non-consumable, store
  price tier €4.99. Bought once (`"once"`) and kept for good (`"kept"`).
- Owned: the id is in `Profile.packs_bought`, like the once-only Starter pack.
  That key is part of the save the server keeps (`ProfileSync`,
  `Profile.cloud_dict`), and `Profile.merge_cloud` joins bought packs, so a
  reinstall or a second phone gets the pass back with the save.
- Restore: `StoreService.restore()` asks the store for kept products;
  `restored(ids)` makes main hand out the missing ones
  (`DiamondPacks.restore`). Only kept products are restored, never a pack of
  diamonds. The link is "Restore purchases" at the foot of the Shop, shown
  while the store is open and the pass isn't owned.
- With the pass, `ReviveFlow` offers a revive after every crash that qualifies
  (the run's revive is left and the score is at least `MIN_SCORE`), whether or
  not an ad is loaded. Revive revives at once: no ad, and the day's free
  revives (`DailyRevives`) are not touched, so they are all still there if
  the pass ever goes.
- Nothing else changes: still `MAX_REVIVES := 1`, no sim, replay, checker or
  gameplay-version change, and revived runs keep the heart on the boards.
  The sim never knows why a revive happened, so a pass revive and an ad
  revive replay the same.
- The offer: no day pips, the line "Revive free with your Revive Pass" and a
  small ink "PASS" pill on the Revive button where the "AD" pill would be.
- The Shop: a wide paper card under the Starter pack ("Revive Pass · One per
  run", a heart and "Free revives, no ads", the price on an ink button); an
  ink "Owned" pill instead of the price once bought. The Shop is now taller
  than the smallest phone, so everything under its header scrolls.
- Developer mode: the debug page has "Revive Pass on or off" (docs/DEBUG.md).

Not checked on the server yet, like the diamond packs: there is no app-store
billing (the store is closed in release builds; `SampleStore` in debug
builds pays at once). When Google Play Billing and StoreKit come, the
purchase receipt must be checked on the server before the pass is granted,
and restore must come from the store's purchase history.

## The rule: a revive restarts the current room

After a revive the bird arrives in the **same room again, as if it had just come
through a portal**:

1. Score, coins, flaps, room index, route and the RNG carry on. Nothing is
   rolled back.
2. The room is started fresh (`RoomRuntime.start` with the same `RoomDef`), so
   its hazards are rebuilt from the RNG and its tide, blink and point counters
   reset.
3. The bird is placed at a side wall, at mid height (`SimConfig.BIRD_START_Y`),
   flying level (`vy = 0`), and waits `SimConfig.ARRIVAL_HOLD` ticks with the
   room frozen.
4. Both walls are cleared, then the wall the bird faces gets spikes through the
   normal `_new_wall(side)`.

Which wall it starts from depends on the exit, so the exit can never be lost:

| At death | Bird starts at | Flies toward |
|---|---|---|
| Exit open on wall S | the wall opposite S | S (the exit) |
| Ghost exit on wall S | wall S | the far wall, to score the point that opens it |
| No exit | the wall behind it (from `vx` at death) | the way it was going |

`exit_open`, `exit_preview`, `exit_side` and the exit heights are kept as they
were.

Why this and not "continue in place with a few safe ticks":

- Portal arrival already exists and is already checked for fairness
  (`_go_through`, `ARRIVAL_HOLD`, `tools/arrival_test.gd`,
  `tests/sim/test_rooms_survivable.gd`). Hazards already keep clear of an
  arriving bird through `entry_y()`. A revive reuses that path instead of adding
  a second one.
- Continuing in place would need every hazard (19 kinds) to honour an
  invulnerable bird, and the bird can be inside a spike or below the floor when
  it dies.

Known side effects, accepted:

- Rooms that place coins at room start place them again, so a revive can be
  worth a few extra coins. It is capped by one revive per run.
- `room.points` resets, so rooms whose walls get busier with points in the room
  start a little calmer.

## Sim changes (`sim/`)

`SimConfig`
- `MAX_REVIVES := 1`
- `GAMEPLAY_VERSION` 14 -> 15. Runs without a revive play exactly as before,
  but the bump is still required: the checksum gains a field, and a version 14
  checker must leave revived runs pending instead of rejecting them.

`SimState`
- `var revives := 0`, added to `copy()` and at the end of `checksum()`.

`GameSim`
- `Event.REVIVE`, appended at the end of the enum.
- `func can_revive() -> bool`: dead, not practice, `state.revives < MAX_REVIVES`.
- `func revive() -> bool`: returns false and changes nothing when
  `can_revive()` is false. Otherwise, in this order (the order is part of the
  rules, like `_new_wall`):
  1. `events.clear()`; `state.alive = true`; `death_cause = NONE`;
     `state.revives += 1`.
  2. Pick the facing side from the table above. Put the bird where it will
     arrive (`state.x`, `state.y`, `state.vx`, `state.vy = 0`) **before** the
     room starts, because hazards read the bird in `setup()`. A portal arrival
     differs here: its room starts while the bird is still at the exit wall it
     flew into, so the Bramble Ball ("start in the half away from the bird")
     starts in the half the bird arrives in. With that position a revive in
     Pumpkin Bounce was unsurvivable; with the real position every room passes.
  3. `_enter_room(room.index)`.
  4. Set `state.x` from `room.wall_left()` / `wall_right()`, clear both spike
     masks, `state.arrival_hold = ARRIVAL_HOLD`.
  5. `_new_wall(facing side)`.
  6. `events.append(Event.REVIVE)`.
- `revive()` does not advance `state.tick`. It is called between steps, while
  the sim is dead, so the time spent on the offer or in the ad is not part of
  the run.

Tick meaning: a death in the step for tick T leaves `state.tick == T + 1`. The
revive is recorded as that value. The next step then runs at the same tick.

## Replay (`sim/replay.gd`)

- New field `revive_ticks: PackedInt32Array` (at most `MAX_REVIVES` entries),
  written to the dictionary as `"revives"`. `score`, `coins`, `end_tick` and
  `checksum` are the final values, after the revive.
- `from_sim(sim, taps, revive_ticks)`.
- `simulate(seed, taps, season, revive_ticks = [])`: when the sim is over and
  the next revive tick equals `sim.state.tick`, call `sim.revive()` and carry
  on; otherwise stop. Returns the sim; a new `revives_used` count lets `verify`
  see unused entries.
- `verify()` additionally rejects:
  - more than `MAX_REVIVES` entries, or entries not ascending and non-negative
    ("invalid revives");
  - an entry that was never used, that is, the bird was not dead at that tick
    ("revive without a death").
- A revived run sent without its revive tick simply fails as "score mismatch",
  as any edited run does today.

## Server

- `RunChecker._replay` reads `revives` like `_taps` (a list of numbers, else
  `rejected: invalid revives`) and passes it on. A missing value means none.
- Version 14 runs become `outdated` once the checker has 15. That is today's
  rule for any gameplay change; frozen older sims are still on the "to come"
  list in ARCHITECTURE.md.
- New migration:
  - `runs.revives jsonb not null default '[]'`.
  - `submit_run(..., p_revives jsonb default '[]')`, rejecting anything but an
    array of at most one element.
  - `worker_pending_runs` and `get_run` return `revives`.
  - `get_board` returns `revived` (true when the list is not empty) for the
    heart mark.
- Deploy the migration before the client that can revive. The client's
  fallback to older `submit_run` argument lists (`NEWER_ARGS`) must not drop
  `p_revives`: a revived run sent without it would be rejected. Without the new
  server, a revived run stays in the send queue.

The server proves that a revive happened at that tick and that there was only
one. It cannot prove an ad was watched or that a free revive was left. That is
accepted for now; closing it needs server-side ad reward callbacks and a
per-player daily counter.

## Client (`game/`, `meta/`, `services/`)

`RunController`
- Keeps `_revive_ticks` next to `_taps`; `replay()` builds the `Replay` so far.
- `died(replay)` still fires on every crash, with the replay up to there.
- `revive()` calls `sim.revive()`, records the tick, refreshes `prev_state` and
  emits `revived`. `can_revive()` is false for practice and replays.
- Watching a replay: a crash at a recorded revive tick (`ReplayDriver.revive_at`)
  revives at once instead of emitting `died`.

`main.gd` on `died` in a real run:
- the run has its revive left, the score is at least `REVIVE_MIN_SCORE`, and
  the player has the Revive Pass, a free revive is left or an ad is ready:
  `Hud.revive_offer.show_offer(...)`.
  The crashed replay waits in `_offer_replay`; taps beside the buttons do
  nothing;
- Revive: free with the Revive Pass, else a free revive if the day has one
  (saved at once), else `ads.show_rewarded()`; `EARNED` and `FAILED` revive,
  `DISMISSED` ends the run;
- Skip, a second crash, or no offer: `_finish_run(replay)` (coins, best score,
  `submit_run`, Game over with "Revived at N").
- After a revive the run is paused with "Tap to flap"; the tap resumes it. That
  tap falls in the arrival hold and is ignored by the sim, as on a portal
  arrival.

`services/ads_service.gd` (`AdsService`): `is_ready()`, `preload_rewarded()`,
`show_rewarded()` and `rewarded_closed(result)`. The base class is "no ads".
`AdmobAds` (`services/admob_ads.gd`) is the real one: `Main._make_ads()` loads
it on a phone whose build has the plugin's native side. `FakeAds` (always
ready, ends at once) stands in on a PC in debug builds and in tests; a release
build without the plugin has no ads and only offers the free revives.
`revive_unit()` gives Google's test unit in debug builds and ours in release
builds. `AdsService.current` lets the Settings sheet show "Ad choices" where
the player has a privacy choice to change. The game is muted while an ad shows.

`game/ui/revive_offer.gd` (`ReviveOffer`): the offer from the mockup, laid out
like Paused. `meta/profile.gd`: `free_revives_used` and the local date they
belong to, `FREE_REVIVES_PER_DAY := 3`; spent only when Revive is pressed.

Views: `revived` plays the `revive` sound and lifts the death low-pass
(`AudioDirector`), shows the arrival portal and flash (`RoomView.on_revived`)
and restarts the trail. Hazards are drawn from `sim.room.hazards`, so the fresh
room shows by itself.

Boards: `LeaderboardBoard.Entry.revived` puts a small ink heart next to the
score in rows and on the podium. `SupabaseLeaderboard` sends `p_revives` only
for a revived run, and keeps such a run in its queue while the database
answers 404 (the migration is not deployed yet).

Open points:
- If the app is killed while the offer is showing, the run is never sent.

## Tests

- `tests/unit/test_revive.gd`
  - revive keeps score, coins and RNG state, bumps `revives`, emits `REVIVE`;
  - a second revive, a revive while alive and a revive in practice return
    false and change nothing (same checksum);
  - the three exit cases from the table put the bird on the right wall facing
    the right way, with the exit still open or still a ghost.
- `tests/unit/test_replay.gd` additions: a revived run verifies; the same run
  with the revive tick removed, moved by one, or doubled is rejected; the
  dictionary round trip keeps `revives`.
- `tests/sim/test_revive_survivable.gd`: for every room kind, kill the bird,
  revive, and let `SurvivalSearch` show that a survivor exists. The search is
  slow, so the check runs one exit case per room (all three come up across the
  rooms); all rooms x all three cases passed once when revive was added. Mid
  height is good enough.
- Two golden replays with a revive (`g15_revived_seed_*.json`); the others
  were regenerated after the version bump and kept their taps, score and end
  tick.
- `RunChecker` tests: `revives` missing, valid, and not a list.
- `tests/unit/test_sim_purity.gd` already covers the new sim code.
- `tests/unit/test_revive_pass.gd`: the pass. The offer with and without it,
  the day's count untouched, no offer still below the score and in a second
  crash, buying it in the Shop ("Owned"), the save round trip, the server
  merge after a reinstall, and restore (kept products only).
- `tests/unit/test_revive_flow.gd`: the app side. Free revives per day, the
  offer's two states, revive then tap then a second crash, Skip, no offer for
  low scores and practice, the ad watched, closed early and broken, a revived
  run played back from the boards, what is sent, and the heart on the boards.

## Milestones

1. **Sim, replay, checker and tests** (this document up to "Server", without
   the migration). Headless only; nothing to playtest yet.
2. **Offer with free revives**: `RunController`, `main.gd`, the two offer
   states and the game-over line from the mockup, the profile counter, the
   migration and the heart on the boards. Playable and shippable without ads.
3. **Ads**: `services/ads` behind `show_rewarded_revive()`, consent flow, the
   ad state of the offer.

## AdMob

Not secrets; all four ship inside the app (`AdsService.ADMOB`). Neither app is
linked to a store listing yet. Debug builds use Google's test ad units, never
these.

| | App ID | Rewarded ad unit "Revive" |
|---|---|---|
| Android | `ca-app-pub-6064406000465979~6679947541` | `ca-app-pub-6064406000465979/7728150383` |
| iOS | `ca-app-pub-6064406000465979~2942727569` | `ca-app-pub-6064406000465979/8849660366` |

Both units: direct AdMob, no partner bidding, reward 1 "Reward".

### The plugin

`addons/admob` is the Poing Studios AdMob plugin v5.1.0 (MIT), unchanged, with
only its core "ads" library for Android (`android/bin/ads`) and iOS
(`ios/bin/ads`) from the plugin's Godot 4.7.2 templates; no mediation adapters. The
libraries are committed, so builds download nothing. It is enabled in
`project.godot` (`[editor_plugins]`), where the two app ids are set too
(`[admob]`); its export plugin writes them into the Android manifest and the
iOS `Info.plist`.

- Android: the plugin only works through Godot's Gradle build, so both Android
  presets use it now and CI installs the build template for every export.
- iOS: the export adds the plugin's framework and Google's SDK as a Swift
  package. The iOS preset carries `NSUserTrackingUsageDescription` for Apple's
  tracking prompt.
- Only the plugin's runtime scripts go into the game (`exclude_filter` in
  `export_presets.cfg`); its samples, mocks, editor code and C# are left out.

### What `AdmobAds` does

1. `start()` (once, when the game opens): asks Google's consent service what
   this player must be asked and shows the consent form when it is required
   (Europe). Ads start only with consent obtained or not required.
2. Starts the SDK with ad content capped at "PG", then keeps one rewarded ad
   loaded (asked for at every run start).
3. `show_rewarded()`: `EARNED` when the reward callback came before the ad
   closed, `DISMISSED` when it closed without one, `FAILED` when it could not
   be shown.

### Not tested, and what to do by hand

- No build with the plugin has been made: this PC has no JDK 17, and iOS needs
  a Mac. The first Android build from CI is the real test. Godot here is
  4.7.2-stable and the libraries were built for 4.7.2. The Android libraries are
  the same for every Godot version; the iOS ones are not, so replace
  `addons/admob/ios/bin/ads` from the plugin's matching `ios-template-v<version>.zip`
  whenever `GODOT_VERSION` changes.
- Test on a phone with a **debug** build (Google's test ads): the consent form
  in Europe, the ad, the reward, closing early, flight mode.
- AdMob console, Privacy & messaging: create the European consent message (and
  the IDFA message for iOS). Without one the form never shows and European
  players get no ads.
- Play Console: declare that the app contains ads and fill in Data safety.
- After publishing, link each AdMob app to its store listing.
