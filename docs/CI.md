# CI: phone builds on GitHub Actions

Three workflows in `.github/workflows/` build Spikey for phones. The repo has **no GitHub
remote yet**, so none of this has run on GitHub. Create the repo, push, add the secrets below,
then start the workflows from the Actions tab.

| Workflow | File | Runs when | Runner | Output |
| --- | --- | --- | --- | --- |
| Check | `check.yml` | push to `main`, pull requests, manual, and as step 1 of the two below | Linux | pass / fail |
| Android Build | `android.yml` | manual (`workflow_dispatch`), tags `v*` | Linux | APK, plus AAB on tags or when "Build AAB" is ticked |
| iOS TestFlight | `ios-testflight.yml` | manual, tags `v*` | Linux, then macOS | build in TestFlight, IPA artifact |

Release flow: bump `config/version` in `project.godot`, commit, then
`git tag v0.1.0 && git push origin v0.1.0`. That runs both phone workflows.

## What each workflow does

**Check** is the Linux version of `tools/check.ps1`: gdlint and gdformat, headless import, load
every script and scene (`tools/ci/load_all.gd`), then `tests/run_tests.gd`. Both phone
workflows call it first, so a failing test stops the build.

**Android Build**

1. Version code = number of commits (`git rev-list --count HEAD`), version name =
   `config/version` from `project.godot`. Both are written into `export_presets.cfg` on the
   runner only.
2. Installs JDK 17, the Android SDK and Godot plus export templates (cached after the first run).
3. With the keystore secrets: exports a release-signed APK and, for `v*` tags or the "Build AAB"
   option, a release-signed AAB through Godot's Gradle build (preset "Android AAB").
   Without them: a debug-signed APK, signed with a key made fresh on each run.
4. Uploads the APK/AAB as artifacts. Download from the run page, unzip, install the APK.

**iOS TestFlight**

1. Linux job: stamps the build number (commit count), version, team id and bundle id into the
   iOS preset, then runs Godot's iOS export with "Export Project Only", which writes a complete
   Xcode project. It removes transparency from the app icons (App Store Connect rejects icons
   with alpha) and uploads the project as an artifact (about 100 MB).
2. macOS job: fastlane (`.github/ios/fastlane/Fastfile`) imports the certificate and profile,
   switches the project to manual signing, builds a Release archive, uploads it to TestFlight,
   and keeps the IPA as an artifact for 7 days. Capped at 25 minutes.

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

1. Testing: run Android Build, download the APK artifact, install it (allow installs from
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
  in `ios-testflight.yml`. Android ids can never change after the first Play upload.
- **Godot version**: `GODOT_VERSION` in all three workflow files. It must name a release on
  github.com/godotengine/godot-builds (e.g. `4.6.2-stable`). CI downloads the matching export
  templates, so keep it equal to the editor you use locally (`tools/godot_path.txt`, now
  4.6-beta2). Moving everyone to a stable 4.6.x release is recommended.
- **Icons**: both platforms use `icon.svg` for now. For a sharper store icon, add a square,
  full-bleed 1024×1024 PNG and set `icons/icon_1024x1024` (iOS) and the
  `launcher_icons/*` options (Android adaptive icon) in `export_presets.cfg`.
- **Devices**: iOS is iPhone-only (`application/targeted_device_family=0`); set 2 for iPhone and
  iPad. Android ships arm64 and armv7.
- **macOS image**: `ios-testflight.yml` uses `macos-15` with the newest stable Xcode. Apple needs
  the iOS 26 SDK for uploads; if that build step reports an old SDK, switch to a newer image.

## Project setting changed for exports

`rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot`. Godot refuses
Android and iOS exports without it. It only adds mobile texture formats to the import; the
game's SVG textures are lossless, so nothing looks different.

## Tested and untested

Tested on this PC (Godot 4.6-beta2, headless): the presets load, the iOS Xcode project export
works with the stamped version and team id, the icon flattening works, and the workflow YAML
parses. Not tested: the Android export (needs JDK 17, which this PC lacks), anything on
GitHub's runners, signing, and the TestFlight upload.
