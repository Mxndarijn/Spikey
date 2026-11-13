# CI: phone builds on GitHub Actions

Two workflows in `.github/workflows/` test and build Flapjaw for phones.

| Workflow | File | Runs when | Runner | Output |
| --- | --- | --- | --- | --- |
| Check | `check.yml` | any push (not docs-only), pull requests, manual, and from Phone builds; full tier on `main`, manual and Phone builds, unit tier elsewhere | Linux, several jobs side by side | pass / fail |
| Phone builds | `build.yml` | manual (`workflow_dispatch`, tick Android and/or iOS), tags `v*` (both) | Linux, macOS for the TestFlight job | APK (plus AAB on tags or when "Build AAB" is ticked), build in TestFlight, IPA artifact |

Release flow: bump `config/version` in `project.godot`, commit, then
`git tag v0.1.0 && git push origin v0.1.0`. That runs Phone builds for both platforms.
A test build: Actions tab, Phone builds, Run workflow (both platforms are ticked by default).

## Local check: unit and integration tiers

`tools/check.ps1` has two tiers, and so does CI (`check.yml`, see "What each workflow does"):
the full tier on `main`, manual runs and Phone builds, the unit tier for pull requests and
pushes to other branches.

- **Unit** (the default): what the files you changed need, judged against the merge-base with
  `-Base` (default `next-features-2`), committed, uncommitted and untracked.
  `tools/ci/select_checks.ps1` picks it and the check prints the reasons first. Lint, format,
  import and the load step always run; a docs-only change runs nothing.
- **Integration** (`-Full` or `-Integration`): everything, including the golden replays, the
  full FastSim-RS parity, sameseed and the other slow whole-game tests. Run it at the version
  bump, before merging `next-features-2` into `main`, and once as a baseline before a batch of
  fixes, so you know the branch is green before building on it.

| changed | Godot tests | parity | FastSim checks |
| --- | --- | --- | --- |
| docs, `*.md` | none | no | none |
| `game/`, `meta/`, `services/`, `server/`, `assets/`, scenes | all but the integration ones | no | `yardstick` when `game/run/` changed (the painters' visible list) |
| one room or hazard: `sim/hazards/*.gd`, `sim/rooms/catalog_*.gd`, `sim/rooms/room_pacing.gd` | all but the integration ones (a catalog or pacing change also runs `test_generated_variants`: the room draws move) | quick | the room checks: passable, arrival, revive, points, keys, crawl, gates, isles, rescued, runs, sight, blind_seeds, yardstick, difficulty (boss files add bossfair) |
| any other `sim/` file (shared) | all but the goldens | quick | all but sameseed |
| `tools/fastsim-rs/` | none | quick | the room checks |
| a test file `tests/**/test_*.gd` | that file | no | none |
| other files under `tests/` (the runner, support) | all but the goldens | no | none |
| other `tools/` files | none | no | none |
| anything else (`project.godot`, workflows) | all but the integration ones | no | none |

Integration-only Godot tests: `test_golden_replays`, `test_generated_variants`, `test_portals`,
`test_arrival_check`, `sim/test_exits_reachable`, `sim/test_crawl_passable`. Integration-only
FastSim checks: sameseed, reach, exits, bossfair.

```
powershell -ExecutionPolicy Bypass -File tools/check.ps1                      # unit tier
powershell -ExecutionPolicy Bypass -File tools/check.ps1 -Full                # integration tier
powershell -ExecutionPolicy Bypass -File tools/check.ps1 -Plan                # what the unit tier would run, and why
powershell -ExecutionPolicy Bypass -File tools/check.ps1 -Files sim/game_sim.gd -Plan
powershell -ExecutionPolicy Bypass -File tools/ci/select_checks.ps1 -SelfTest  # the rules on real commits
```

Measured 2026-11-13 on `next-features-2`, `-Jobs 4 -FastSimJobs 4`, one CPU slot:

| Change | Tier | Wall time |
| --- | --- | --- |
| everything (`-Full`), before | integration | 364 s |
| everything (`-Full`), generated variants in parallel | integration | 252 s |
| a painter (8b05cc3) | unit | 46 s |
| a world scene (62aca6f lantern) | unit | 46 s |
| a room fix (f7bc459, two hazards + rust) | unit | 47 s |
| room pacing (c3ab062, moves the draws) | unit | 202 s |
| a shared `sim/` file | unit | close to `-Full` (skips only the goldens and sameseed) |
| docs only | unit | 0 s |

Selection is by layer, not by file: almost every test reaches `sim/` through `class_name`
globals, so following imports would select nearly everything. A `sim/` file that is not on the
room-or-hazard list counts as shared, so a wrong guess runs more, not less. A failure only the
integration tier finds shows up at the baseline or the release run and needs bisecting over that
batch.

## What each workflow does

**Check** is the Linux version of `tools/check.ps1`, split into jobs that run side by side, each
on its own 4-core runner:

| Job | What | Healthy time (full tier) |
| --- | --- | --- |
| `plan` | picks the tier and what it runs (`tools/ci/select_checks.ps1`, the same rules as the local unit tier) | ~15 s |
| `godot` | gdlint and gdformat, headless import, load every script and scene (`tools/ci/load_all.gd`), `tests/run_tests.gd` one worker per core | about 4 min (Tests about 3 min) |
| `fastsim` | builds FastSim-RS (cached), runs the parity check, hands the binary on | about 1.5 min with the cargo cache, 2.5 min without |
| `fastsim_checks` | the bot-heavy FastSim-RS checks, one job per group (matrix) | about 2 min per group, after `fastsim` |

The full tier (pushes to `main`, manual runs, every run Phone builds calls) runs everything. The
unit tier (pull requests, pushes to other branches) runs what the files changed against the
merge-base with `main` need, as `tools/check.ps1` does locally; the `plan` job's log says what
it picked and why. The run passes only when every job passes or is skipped because the tier
needs nothing.

The FastSim checks are grouped by measured length (`plan` job, `$groups`): `reach`, `sameseed`, and the other sixteen together (`exits` the largest of them). Measured 2026-11-13, each check alone with `--jobs 4`: `reach` and `sameseed` about 40% of the time each, `exits` 10%, `yardstick` 7%, `bossfair` and `passable` 3% each, the other twelve 1% together. A check
missing from the list runs in the last group; when a group grows much longer than the others,
move a check. The Rust toolchain is pinned (`RUST_TOOLCHAIN` in `check.yml`, keep it equal to the
local `rustc --version`) and the cargo cache key names the exact compiler, so a new Rust release
no longer makes the cached build stale. The Tests, parity and checks steps stop after 15 minutes,
so a hung test fails in minutes instead of holding the job for 40.

Phone builds runs the
tests once for both platforms, next to the builds, so the builds don't wait for them; the
steps that ship (GitHub Release, Discord post, TestFlight) wait for them to pass. When the
commit already has a Check run from its push to `main`, Phone builds uses that run instead of
testing the same code again (job `check_reuse`): a passed run counts, a running one is waited
for. Only full-tier Check runs count: a push to `main` or a manual run (a pull request run tests
a merge with the base branch, not the commit, and branch pushes get the unit tier). With no such
run, or a failed one, Phone builds runs the full tier itself. A newer push to a pull request or
to a branch other than `main` cancels its older Check run.

To verify on the first push of this layout (it could not run on GitHub before):

Expected: about 4 to 5 minutes for a full run (was 11.4 min for v22 with everything in one job),
so a release (Phone builds) takes about 7 to 8 minutes.

1. A push to `main`: the run shows Plan, Lint and Godot tests, FastSim-RS build and parity, and
   one FastSim-RS checks job per group, all passing; the Plan log says `Tier: full`.
2. The `fastsim` job: "Cache cargo" misses once (the key now names the compiler), saves, and the
   next push restores it; "Build FastSim-RS" then takes seconds, not about 70 s.
3. Phone builds on that commit: "Find the tests of this commit" reuses the run and its own Check
   is skipped.
4. A pull request or a push to another branch: `Tier: unit` with the reasons, and only the picked
   tests and groups run.

**Phone builds, Android** (jobs `android_*`)

1. Version code = number of commits (`git rev-list --count HEAD`), version name =
   `config/version` from `project.godot`. Both are written into `export_presets.cfg` on the
   runner only.
2. Installs JDK 17, the Android SDK and Godot plus export templates (cached after the first
   run, as are Gradle and the libraries its build downloads).
3. With the keystore secrets: exports a release-signed APK and, for `v*` tags or the "Build AAB"
   option, a release-signed AAB. Both go through Godot's Gradle build, which the AdMob plugin
   (`addons/admob`, the rewarded ad for the revive) needs; the first export installs the build
   template into `android/` (ignored by git); CI installs it by hand and patches it, so the
   export must not pass `--install-android-build-template` (that reinstalls the stock one).
   Without them: still a release APK, signed with a key made fresh on each run.
   Before the export, CI turns on R8 code shrinking (`tools/ci/patch_android_shrink.sh`) and
   puts the small engine in the template (`tools/ci/swap_android_engine.sh`, see below).
4. Uploads the APK/AAB as artifacts (kept 90 days, need a GitHub login).
5. A separate job, once the build is done and the tests have passed, publishes the APK as a
   GitHub Release, a direct public download because the repo is
   public: `v*` tags become a release named after the version, other runs a pre-release
   tagged `build-<n>`. Old test pre-releases pile up; delete them on the Releases page
   (also delete the tag) when the list gets long.
6. Posts a Discord embed whose button downloads that APK (when `DISCORD_WEBHOOK_URL` is set).

**Phone builds, iOS** (jobs `ios_*` and `testflight`)

1. Linux job: stamps the build number (commit count), version, team id and bundle id into the
   iOS preset, then runs Godot's iOS export with "Export Project Only", which writes a complete
   Xcode project. It removes transparency from the app icons (App Store Connect rejects icons
   with alpha) and uploads the project as an artifact (about 100 MB).
2. macOS job, once the export is done and the tests have passed: fastlane (`.github/ios/fastlane/Fastfile`) imports the certificate and profile,
   switches the project to manual signing, builds a Release archive, uploads it to TestFlight,
   and keeps the IPA as an artifact for 7 days. Capped at 25 minutes.

**Engine** (`engine.yml`, called by Phone builds for each platform) builds the small engine: Godot from
source at the exact `GODOT_VERSION`, 2D only, without the modules the game doesn't use
(`tools/engine/flapjaw.py`). The stock engine is about 90% of each build. Android builds on
Linux, iOS on macOS. The result is cached, so only a change to `tools/engine/`, `engine.yml`
or the Godot version compiles again (a cold build takes a long time; a cache hit takes
seconds). Before turning off another module, check that nothing exported uses it: a class
missing from the engine fails when the game loads on the phone, not in the check.
The iOS engine also gets Flapjaw's own modules from `tools/engine/modules` (`custom_modules`):
`flapjaw_keychain`, the `FlapjawKeychain` singleton that keeps the device key in the Keychain
(`docs/LEADERBOARD_SETUP.md`). Compiled with the engine, it uses exactly its headers and flags,
and `#import <Security/Security.h>` with clang modules links Security.framework, so the Xcode
project needs no change. The build fails if the module is missing from the library.

The iOS build uses Godot's stock engine unless a manual run turns on "small_engine":
build 127, the first one tested with the small engine, crashed at launch on iOS 27 inside the
engine's own Swift startup code (`SwiftUIApp.body`), and the stock engine (build 58) starts
fine. Until that is solved, iOS builds are larger and have no `FlapjawKeychain`, so the device
key lives in the file only and a reinstall is a new player there. Android still uses the
small engine.

## Secrets

Add them under GitHub repo → Settings → Secrets and variables → Actions → New repository secret.
The iOS names are the same as in the Schietvereniging project, so the values you already made
there can be reused, except the provisioning profile and its name (that one is per app).

### Android

| Secret | What |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The upload keystore file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password (also used as the key password) |
| `ANDROID_KEY_ALIAS` | Key alias inside the keystore, e.g. `spikey` |
| `DISCORD_WEBHOOK_URL` | Optional, shared with iOS. Discord channel → Edit Channel → Integrations → Webhooks → New Webhook → Copy Webhook URL. Every successful Android build and TestFlight upload posts an embed (version, build, type, commit; Android also attaches the APK when it fits). |

Optional repository **variable** (Settings → Secrets and variables → Actions → Variables): `DISCORD_MAX_UPLOAD_MB`, the server's upload limit (10 normally, 50 at boost level 2, 100 at level 3). Larger APKs are only linked. Zipping does not help: an APK is already a compressed zip.

All three are optional for testing: without them you get a debug APK. They are required for an
AAB and for any APK you want to update in place later.

Make the keystore once and **back it up** (losing it means you can never update the app outside
Play App Signing):

```bash
keytool -genkeypair -v -keystore spikey-upload.keystore -alias spikey -keyalg RSA -keysize 2048 -validity 10000
```

Give the same password for store and key (Godot uses one password for both). Then encode it:

```bash
base64 -w0 spikey-upload.keystore > keystore.b64
```

On Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("spikey-upload.keystore")) | Set-Content keystore.b64`.
Paste the contents of `keystore.b64` into `ANDROID_KEYSTORE_BASE64`, then delete `keystore.b64`.
Never commit the keystore.

`keytool` comes with any JDK 17+ (the JDK 8 on this PC also has one and works for this).

### iOS

| Secret | What | How to get it |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10-character team id | developer.apple.com → Account → Membership details |
| `IOS_DIST_CERT_P12_BASE64` | Apple Distribution certificate + private key, `.p12`, base64 | Keychain Access on a Mac: export the "Apple Distribution: …" certificate with its key as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `IOS_P12_PASSWORD` | Password you set when exporting the `.p12` | |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile for `com.mxndarijn.spikey`, base64 | developer.apple.com → Profiles → + → App Store Connect → pick the app id and the distribution certificate → download, then `base64 -i Spikey_AppStore.mobileprovision \| pbcopy` |
| `IOS_PROVISIONING_PROFILE_NAME` | The profile's name exactly as shown on developer.apple.com | e.g. `Spikey App Store` |
| `ASC_KEY_ID` | App Store Connect API key id | App Store Connect → Users and Access → Integrations → App Store Connect API → + (role App Manager) |
| `ASC_ISSUER_ID` | Issuer id shown above the key list | same page |
| `ASC_KEY_CONTENT_BASE64` | The downloaded `AuthKey_XXXX.p8`, base64 | `base64 -i AuthKey_XXXX.p8 \| pbcopy` (the `.p8` can only be downloaded once) |

On Windows, base64-encode a file with the PowerShell line from the Android section.

## Things to do by hand

**GitHub**

1. Create the repository and push `main`. Actions must be enabled (default).
2. `export_presets.cfg` is listed in `.gitignore`. Remove that line so the presets get
   committed; the workflows need them. The file contains no secrets: Godot keeps export
   passwords in `.godot/export_credentials.cfg`, and CI passes the keystore through
   environment variables.
3. Add the secrets above.

**Android**

1. Testing: run Phone builds (untick iOS if you only want Android), download the APK artifact, install it (allow installs from
   unknown sources). Debug builds use a new key each run, so uninstall the previous one first.
2. Play Console (only when you want Play testing): pay the one-time developer fee, create the
   app with package name `com.mxndarijn.spikey`, enable Play App Signing, and upload the
   first AAB by hand under Testing → Internal testing. Uploading from CI automatically can be
   added later (it needs a Google service account).

**iOS**

1. Paid Apple Developer Program membership.
2. developer.apple.com → Identifiers → + → App ID with bundle id `com.mxndarijn.spikey`
   (no extra capabilities needed).
3. An Apple Distribution certificate (reuse the Schietvereniging one if it is in the same team)
   and an App Store provisioning profile for the new app id.
4. App Store Connect → Apps → + → new app with that bundle id. TestFlight uploads fail until the
   app record exists.
5. After the first upload, answer the export compliance question if asked (the build already
   says it uses no non-exempt encryption) and add yourself as an internal tester.

## Changing things

- **App id / bundle id**: `package/unique_name` (presets "Android" and "Android AAB") and
  `application/bundle_identifier` (preset "iOS") in `export_presets.cfg`, plus `IOS_BUNDLE_ID`
  in `build.yml`. Android ids can never change after the first Play upload.
- **Godot version**: `GODOT_VERSION` in `check.yml`, `build.yml` and `verify-runs.yml`, plus
  `godot_version` in the `android_engine` and `ios_engine` jobs of `build.yml` (the builds fail
  if they differ). It must name a release on
  github.com/godotengine/godot-builds (e.g. `4.7.2-stable`). CI downloads the matching export
  templates, so keep it equal to the editor you use locally (`tools/godot_path.txt`, now
  4.7.2-stable). The iOS AdMob libraries are built per Godot version (see `docs/REVIVE.md`).
- **Icons**: both platforms use `icon.svg` for now. For a sharper store icon, add a square,
  full-bleed 1024×1024 PNG and set `icons/icon_1024x1024` (iOS) and the
  `launcher_icons/*` options (Android adaptive icon) in `export_presets.cfg`.
- **Devices**: iOS is iPhone-only (`application/targeted_device_family=0`); set 2 for iPhone and
  iPad. Android ships arm64 only.
- **macOS image**: the `testflight` job in `build.yml` uses `macos-15` with the newest stable Xcode. Apple needs
  the iOS 26 SDK for uploads; if that build step reports an old SDK, switch to a newer image.

## Project setting changed for exports

`rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot`. Godot refuses
Android and iOS exports without it. It only adds mobile texture formats to the import; the
game's SVG textures are lossless, so nothing looks different.

## Tested and untested

Tested on this PC (Godot 4.6-beta2, headless; the full check also passes on 4.7.2-stable): the presets load, the iOS Xcode project export
works with the stamped version and team id, the icon flattening works, and the workflow YAML
parses. Not tested: the Android export (needs JDK 17, which this PC lacks), anything on
GitHub's runners, signing, and the TestFlight upload.

The small engine (`engine.yml`, R8, the template swaps) is checked only on GitHub's runners:
Godot's Android and iOS engines can't be built on this PC. Playtest the rewarded ad and push
alerts on both phones after an engine change: the plugins talk to the engine directly.
