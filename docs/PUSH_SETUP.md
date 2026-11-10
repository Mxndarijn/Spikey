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
   line (`supabase/migrations/20261110110000_push_alerts.sql`).
3. If an alert was queued, the database calls the Edge Function
   `supabase/functions/send-alerts`, which sends it through Firebase Cloud
   Messaging and reports back what was sent.

Without the setup below nothing is sent; the line on Home still works.

## One-time setup

1. **Firebase**: create a project at <https://console.firebase.google.com>, add
   an Android app with package name `com.mxndarijn.spikey`, and download
   `google-services.json` (the Android build needs it later).
2. **Service account key**: Project settings -> Service accounts -> Generate
   new private key. This file can send notifications as your app: never commit
   it or share it. If it leaks, delete that key on the same page (Manage
   service account permissions -> Keys) and generate a new one.
3. **GitHub secrets** (Settings -> Secrets and variables -> Actions):

   | Secret | Value |
   |---|---|
   | `FIREBASE_SERVICE_ACCOUNT` | The whole contents of the service account key file |
   | `PUSH_SEND_SECRET` | Any long random text (for example 40 letters and digits) |
   | `SUPABASE_ACCESS_TOKEN` | Supabase -> Account -> Access Tokens -> Generate new token |
   | `SUPABASE_PROJECT_REF` | The id in the project's URL (`https://<this>.supabase.co`) |
   | `SUPABASE_DB_URL` | Already there from `docs/LEADERBOARD_SETUP.md` |

4. **Deploy**: the workflow `.github/workflows/supabase-functions.yml` runs when
   `supabase/functions/` changes on `main`, or by hand (Actions -> Supabase
   functions -> Run workflow). It deploys the function, gives it its secrets and
   tells the database where it lives.

## Testing without phones

- `powershell -ExecutionPolicy Bypass -File tools/db_test.ps1`: the migrations
  and `supabase/tests/` against a throwaway Postgres.
- `powershell -ExecutionPolicy Bypass -File tools/functions_test.ps1`: the Edge
  Function with stand-ins for Firebase and the database.

Both need Docker running. Neither touches the live project.

## Not there yet

- The native plugin that gets a push token on Android and iOS. Until it is in,
  no phone registers and every alert is stored as `no_device`.
- iOS needs an Apple push key uploaded to the same Firebase project.
