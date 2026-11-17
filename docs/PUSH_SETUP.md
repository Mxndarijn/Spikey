# Board alerts (push notifications)

A player gets a notification when another player's checked run pushes them past
a prize line on the Daily board: out of 1st, 2nd, the podium or the top 10.
Each line alerts once a day, and never between 22:00 and 08:00 on the phone's
clock. The same words show as a line on Home when the game is open.

## How it works

1. The game hands the server its push token (`register_push`) and the Board
   alerts switch (`set_push_enabled`). See `services/push_service.gd`.
2. When the run checker passes a run, the database compares today's places with
   the ones it remembered and writes an alert for everyone who dropped past a
   line (`backend/migrations/20261110110000_push_alerts.sql`).
3. The game server sends the queued alerts through Firebase Cloud Messaging
   and writes back what was sent (`backend/src/push.rs`).

Without the setup below nothing is sent; the line on Home still works.

## One-time setup

1. **Firebase**: create a project at <https://console.firebase.google.com>, add
   an Android app with package name `com.mxndarijn.spikey`, and download
   `google-services.json` (the Android build needs it later).
2. **Service account key**: Project settings -> Service accounts -> Generate
   new private key. This file can send notifications as your app: never commit
   it or share it. If it leaks, delete that key on the same page (Manage
   service account permissions -> Keys) and generate a new one.
3. **The server**: put the key file, in base64, in `FIREBASE_SERVICE_ACCOUNT`
   of the server's `.env.<env>` (docs/DEPLOY.md, "Settings and secrets") and
   deploy. Without it the server logs "board alerts are not sent" and sends
   nothing.

## Testing without phones

- `powershell -ExecutionPolicy Bypass -File tools/db_test.ps1`: the migrations
  and `backend/sql_tests/` against a throwaway Postgres.
- `powershell -ExecutionPolicy Bypass -File tools/backend_test.ps1`: the server,
  its alert sender's unit tests included (`backend/src/push.rs`).

Both need Docker running for the database parts. Neither touches the live
server.

## Not there yet

- The native plugin that gets a push token on Android and iOS. Until it is in,
  no phone registers and every alert is stored as `no_device`.
- iOS needs an Apple push key uploaded to the same Firebase project.
