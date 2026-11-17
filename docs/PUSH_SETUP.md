# Push notifications (board and battle alerts)

Two kinds, each on its own Android channel:

- **Board alerts** (`board_alerts`): another player's checked run pushes you
  past a prize line on the Daily board: out of 1st, 2nd, the podium or the top
  10. Each line alerts once a day, never between 22:00 and 08:00 on the
  phone's clock. The same words show as a line on Home when the game is open.
- **Battle alerts** (`battles`): your turn, nudges and results.

Settings > Board alerts is the one switch for both (the server keeps one per
phone).

## How it works

1. **Permission.** Android 13+ and iOS ask the player once, at the first
   moment it means something: the first prize spot on the Daily board, or the
   first battle loaded (`game/app/board_alerts.gd`). The Godotx Firebase plugin
   shows the OS prompt (`request_permission`).
2. **Token.** Android hands out an FCM token without asking, so every start
   fetches one. iOS goes through `request_permission` at every start once the
   player answered (no prompt then): that registers the app with Apple again,
   and only then does Firebase hand out the token. See
   `services/firebase_push.gd`.
3. **Registration.** The token goes to the server (`register_push`, signed in
   as the player; table `push_devices`). One the server didn't take (no network,
   a new player after a transfer) is sent again at the next sign-in or board
   load (`services/push_service.gd`).
4. **Channels.** Android 8+ gets both channels at start
   (`services/android_channels.gd`); the ids match `backend/src/push.rs`.
5. **Queue.** The database writes alerts into `spot_alerts` and
   `battle_alerts`: `queued` for a phone in `push_devices` with alerts on,
   `no_device` otherwise, `quiet` at night. Alerts older than 30 minutes are
   never sent.
6. **Sending.** The game server sends queued alerts every 30 s through FCM HTTP
   v1 and marks them `sent` or `failed` (`backend/src/push.rs`); a refusal is
   logged with Firebase's error code (never the token). Dead tokens are
   forgotten.

Without `FIREBASE_SERVICE_ACCOUNT` on the server nothing is sent (the log says
"board and battle alerts are not sent" at start); the line on Home still works.

## One-time setup

Never paste any of these files or keys into a chat, an issue or a commit.

### Firebase console (<https://console.firebase.google.com>, the Flapjaw project)

1. **Android app**: Project settings -> General -> Your apps: an Android app
   with package `com.mxndarijn.spikey`. Download `google-services.json` and put
   its whole text in the GitHub secret `GOOGLE_SERVICES_JSON`. No SHA
   fingerprint is needed for push.
2. **iOS app**: an Apple app with the iOS bundle id from `export_presets.cfg`
   (`application/bundle_identifier`). Download `GoogleService-Info.plist` and
   put its whole text in the GitHub secret `GOOGLE_SERVICE_INFO_PLIST`.
3. **APNs key** (iOS only; without it Firebase refuses every iOS message with
   `THIRD_PARTY_AUTH_ERROR`): Project settings -> Cloud Messaging -> Apple app
   configuration -> APNs Authentication Key -> Upload: the `.p8` file, its Key
   ID and your Apple Team ID (see "Apple developer site" below).
4. **Cloud Messaging API (V1)**: Project settings -> Cloud Messaging: "Firebase
   Cloud Messaging API (V1)" must say Enabled. If not, the menu there opens the
   Google Cloud console page to enable it.
5. **Service account key**: Project settings -> Service accounts -> Generate
   new private key. This file can send notifications as your app. If it leaks,
   delete that key (Manage service account permissions -> Keys) and make a new
   one.

### Apple developer site (<https://developer.apple.com/account>)

1. Certificates, IDs & Profiles -> Identifiers -> the app's id: Push
   Notifications ticked. (After ticking it, regenerate the App Store
   provisioning profile and set `IOS_PROVISIONING_PROFILE_BASE64` again; Phone
   builds checks the profile allows push.)
2. Keys -> + -> name it, tick "Apple Push Notifications service (APNs)",
   Continue, Register, Download the `.p8` (one download only: keep it safe).
   Note its Key ID. Your Team ID is under Membership details. One key works
   for both TestFlight and App Store builds.

### The server

Put the service account key file, in base64, in `FIREBASE_SERVICE_ACCOUNT` of
the server's `.env.<env>` (docs/DEPLOY.md, "Settings and secrets"), then
deploy. The start log should no longer say "alerts are not sent".

## Testing on a phone

1. Install a build made after the secrets were set (Phone builds says "Board
   alerts: Firebase" in its log for each platform).
2. Open the game, then open a battle (or reach a top-10 Daily spot): allow
   notifications at the prompt. On Android 12 and older there is no prompt.
3. Debug screen (docs/DEBUG.md) -> Push: "Push: in this build", a Token, and
   "On the server: yes". "Last error" says what went wrong if not.
4. "Send a test notification", then leave the app at once: it arrives within
   about 30 s. The answer says why not ("not registered", "no sender", ...).
5. Android: Settings -> Apps -> Flapjaw -> Notifications lists "Board alerts"
   and "Battles".
6. If nothing arrives, the server log has one line per refused message with
   Firebase's error code: `THIRD_PARTY_AUTH_ERROR` (iOS) is the APNs key,
   `SENDER_ID_MISMATCH` is a service account from another Firebase project,
   `UNREGISTERED` a reinstalled app (the token is then forgotten).

## Testing without phones

- `powershell -ExecutionPolicy Bypass -File tools/db_test.ps1`: the migrations
  and `backend/sql_tests/` against a throwaway Postgres.
- `powershell -ExecutionPolicy Bypass -File tools/backend_test.ps1`: the server,
  its alert sender's unit tests included (`backend/src/push.rs`).

Both need Docker running for the database parts. Neither touches the live
server.
