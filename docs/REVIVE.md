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
- After a revive a 5, 4, 3, 2, 1 counts down over the frozen room, then the
  run plays on by itself. No tap needed; taps during it do nothing.

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

## The rule: a revive restarts the room as the bird came into it

After a revive the run is **exactly as it was when the bird came into the
room**, points and coins included, and the bird is back at the portal it came
through. The rest of the run is the one a player who never died in that room
meets: the same rooms, variants, exits, spikes and coins (two players on one
seed meet the same map, except where they make a real choice; a future 1v1
mode needs this).

1. Everything comes back from the moment the bird came out of the portal
   (`_keep_entry`, at the run start and after every portal arrival, not in
   practice or inside an arrival check): the whole `SimState` (`_entry_state`:
   the bird's wall, height, way and speed, the score, the coins, the room's
   coin, the exit and ghost, the planned exits, the anchor, the wall spikes),
   the room (`_entry_room`: the variant, the hazards where they were then,
   Coin Garden's room coins, Locked Out's key, the tide, blink and point
   counters) and both RNGs (`_entry_rng`, `_entry_spine`).
2. Only three things carry on: the tick (a revive takes no time, and the run
   file counts ticks), the revive count, and the taps (`flaps`, for
   achievements; it changes nothing in play).
3. The bird waits `SimConfig.ARRIVAL_HOLD` ticks with the room frozen, then
   flies on by itself (`started` is set, also in the first room, where the run
   had waited for a first tap). Main counts 5, 4, 3, 2, 1 over it.

So the points and coins collected in that room are gone: the score goes back
down to what it was at the portal, and the coins too. A death on an odd score
no longer flips the exit wall, and the walls of the room are rolled with the
same score as before.

Why this:

- It looks like a real restart, and the replay of a revived run looks like a
  run that never died: same score, same rooms after it.
- The first version kept the score, the coins and the RNG. The walls after the
  revive were then rolled with the higher score (more spikes), the ghost came
  sooner, and a death on an odd score flipped the exit wall (the exit's wall
  goes by score parity, `_maybe_open_exit`): the bird left by the other wall at
  that wall's planned height, every later room was entered from the other side,
  and room kinds, variants and exits differed for the rest of the run. FastSim
  `sameseed` found it on 6 of 6 seeds with a death on a score ending in 5.
- The arrival was already checked for fairness when the bird first came in
  (`_go_through` retries the layout until `ArrivalCheck` passes). The revive
  replays that same arrival, with a longer hold. An exit planned before the
  death plays no part any more: the room is back to before it.
- Continuing in place at the moment of death was ruled out from the start: the
  hazard that killed the bird is still there, every hazard would have to
  honour an invulnerable bird, and the bird can be inside a spike or below the
  floor when it dies.

Known side effects, accepted:

- Coins and keys the room had when the bird came in are back, and so is the
  coin that was out then. The coins taken in the room are gone, so a revive is
  never worth extra coins.
- A room whose walls follow its hazards (Lava Rise, Locked Out's chain) can
  show other spikes when the bird bounces at another tick or with the hazards
  elsewhere, after a revive as for any two players. In Lava Rise that is a
  real choice: the line rises one step per point, the same for everyone, and
  only cooling it (stone, ice, raft) moves it back. (Cold Wall's ice slot once
  read the bird's own height; it reads the anchor now.)
- Where a coin spawns depends on when the last one was taken (a coin appears
  at a bounce only when none is out), a real choice of the player.

## Sim changes (`sim/`)

`SimConfig`
- `MAX_REVIVES := 1`
- `GAMEPLAY_VERSION` 14 -> 15. Runs without a revive play exactly as before,
  but the bump is still required: the checksum gains a field, and a version 14
  checker must leave revived runs pending instead of rejecting them.
- The revive that restores the score, the coins and the RNGs (this rule, and
  `SimState.revive_gap` gone from the checksum) needs a `GAMEPLAY_VERSION`
  bump and new goldens; the coordinator bumps it once everything for
  `next-features-2` is merged. Runs without a revive play exactly as before.

`SimState`
- `var revives := 0`, added to `copy()` and at the end of `checksum()`.

`GameSim`
- `Event.REVIVE`, appended at the end of the enum.
- `func can_revive() -> bool`: dead, not practice, `state.revives < MAX_REVIVES`.
- `_entry_room`, `_entry_state`, `_entry_rng` and `_entry_spine`: the room
  (`SimCopy.copy_room`), the state copy and the two RNGs (`SimCopy.copy_rng`)
  kept by `_keep_entry()` at the run start and at the end of `_arrive_in`.
  Never changed after; a revive copies them again.
- `func revive() -> bool`: returns false and changes nothing when
  `can_revive()` is false. Otherwise:
  1. `events.clear()`; keep the tick, `revives + 1` and `flaps`.
  2. `state.assign(_entry_state)` (in place, so whoever holds `sim.state` sees
     it), then put back the tick, revives and flaps; `started = true`;
     `arrival_hold = ARRIVAL_HOLD`.
  3. `room` = a copy of `_entry_room`; `_rng` and `_spine` = copies of the
     kept ones; `_free_lo`/`_free_hi` cleared.
  4. `events.append(Event.REVIVE)`.
- `revive()` does not advance `state.tick`. It is called between steps, while
  the sim is dead, so the time spent on the offer or in the ad is not part of
  the run.

Tick meaning: a death in the step for tick T leaves `state.tick == T + 1`. The
revive is recorded as that value. The next step then runs at the same tick.

## Replay (`sim/replay.gd`)

- New field `revive_ticks: PackedInt32Array` (at most `MAX_REVIVES` entries),
  written to the dictionary as `"revives"`. `score`, `coins`, `end_tick` and
  `checksum` are the final values, after the revive (the score can be lower
  than the score at the death: the room's points went with the revive).
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
  revives at once instead of emitting `died`, and Main shows the same 5, 4, 3,
  2, 1 over the frozen room as the live revive did (`Main._start_revive_countdown`).

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
- After a revive `Main.REVIVE_COUNTDOWN` (5 s) counts 5, 4, 3, 2, 1 with the
  big `ResumeCountdown` and the bird flies on by itself at 0. The run is
  paused for the first 4 s; the last second is the sim's own revive hold
  (`SimConfig.ARRIVAL_HOLD`, 60 ticks), where the count follows
  `SimState.arrival_hold`. So nothing in `sim/` changed: the resume tick is
  always the revive tick + `ARRIVAL_HOLD`, as before. Main drops taps during
  the whole countdown (none are recorded), and the sim would ignore any in its
  hold anyway. Pause during it stops it; Resume then counts the usual 3, 2, 1.

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
(`AudioDirector`, in the mood of the score the run went back to, and beating
the best again plays the milestone again), shows the arrival portal and flash
(`RoomView.on_revived`) and restarts the trail. The HUD score reads the sim
every frame, so it shows the score going back down at once; the coin counter
is set back too (`Hud.set_run_coins(coins, true)`, coins still flying are dropped).

The score going back down needs nothing else: coins, the best score, the
boards, the run file and Your runs only use the final `Replay` values at
`_finish_run`, and nothing is banked during the run. The day's free revives
count revives, not points. "Revived at N" on Game over and in Your runs is
still the score at the death (`ReviveFlow.revived_at`), so it can be higher
than the final score. Hazards are drawn from `sim.room.hazards`, so the fresh
room shows by itself.

Boards: `LeaderboardBoard.Entry.revived` puts a small ink heart next to the
score in rows and on the podium. `SupabaseLeaderboard` sends `p_revives` only
for a revived run, and keeps such a run in its queue while the database
answers 404 (the migration is not deployed yet).

Open points:
- If the app is killed while the offer is showing, the run is never sent.

## Tests

- `tests/unit/test_revive.gd`
  - revive puts back the score, the coins, the whole state and both RNGs as
    the bird came in (only the tick, revives and flaps carry on), bumps
    `revives`, emits `REVIVE`;
  - a second revive, a revive while alive and a revive in practice return
    false and change nothing (same checksum);
  - the room, the bird and the walls are as the bird came in; an exit at the
    death goes back to the entry and the bird lives through the wait; the
    first room starts where the run did and flies on after the wait;
  - the room's planned exits never move;
  - a revived run meets the same map as a run that never died there (rooms,
    variants, plans and walls), on a death on an even and an odd score.
- The `sameseed` FastSim check (`tools/fastsim-rs/fastsim/src/checks/sameseed.rs`): 24 seeds, a
  death on a score ending in 4 and in 5 in room 2 or later, revived, against
  the same PlannerBot with no death: the same rooms, variants, room seeds,
  plans, ghosts and open exits, and the same walls (a bounce at another tick
  in the room or with the hazards elsewhere checks only side and score; a room
  whose exit opened at another tick ends the comparison, as Bumper Cloud and
  wind move the exit for any two players). `fastsim-rs sameseed <seed> --die 5
  --onlyrevive 1` shows one seed in full.
- `tests/unit/test_replay.gd` additions: a revived run verifies; the same run
  with the revive tick removed, moved by one, or doubled is rejected; the
  dictionary round trip keeps `revives`.
- The `revive` FastSim check (`tools/fastsim-rs/fastsim/src/checks/revive.rs`, was
  `tests/sim/test_revive_survivable.gd`): for every room kind, all three exit
  cases at the death, both exit walls, both ways in and three portal heights
  (140, 300 and 480 px; 1764 cases), the bird comes in through a portal laid
  out as in a real run (`BotSetups.came_in`), dies, is revived, and
  `SurvivalSearch` shows that a survivor exists. The `crawl`, `gates` and
  `isles` searches through an exit behind a revived bird are gone: that exit
  no longer comes back (their setups stay for the parity runs).
- Two golden replays with a revive (`g*_revived_seed_*.json`, regenerated with
  the next version bump); the others
  were regenerated after the version bump and kept their taps, score and end
  tick.
- `RunChecker` tests: `revives` missing, valid, and not a list.
- `tests/unit/test_sim_purity.gd` already covers the new sim code.
- `tests/unit/test_revive_pass.gd`: the pass. The offer with and without it,
  the day's count untouched, no offer still below the score and in a second
  crash, buying it in the Shop ("Owned"), the save round trip, the server
  merge after a reinstall, and restore (kept products only).
- `tests/unit/test_revive_flow.gd`: the app side. Free revives per day, the
  offer's two states, revive then the 5 to 1 countdown (taps ignored, the
  resume tick, the replay) then a second crash, Skip, no offer for
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
