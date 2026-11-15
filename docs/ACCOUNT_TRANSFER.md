# Move to a new phone (plan)

Status: **plan only, waiting on the user's go-ahead.** It is built on the new
server (`docs/SERVER_MIGRATION.md`) after the switch, as its own branch.
Visual version with the screen mockups:
<https://claude.ai/artifact/VWL3jnUqwuM1tTWU8HynT5> (source:
`docs/mockups/account_transfer.html`). Keep both in step.

## Options

| Option | Effort | Personal data stored | Store rules | Lost phone | Android to iPhone |
|---|---|---|---|---|---|
| **Transfer code** (phase 1) | Small: 4 endpoints, 5 screens, no plugins | None, players stay anonymous | Nothing new | No | Yes |
| **Sign in with Apple and Google** (phase 2) | Medium to large: native plugins, token checks | A provider user id; no email unless asked | Apple: Google sign-in needs Sign in with Apple too. Both stores: in-app account deletion once players can make an account; Google Play also a web link | Yes | Yes |
| Email magic link or code | Medium: mail provider, deep links | An email address (GDPR) | Account deletion, privacy policy | Yes | Yes |
| Play Games / Game Center saves | Large: two SDKs, two save systems | Platform player id | Each platform's terms | Same platform | No |

Saved-game blobs don't fit: diamonds, prizes and the ladder are on the server,
so the server must know the player either way. Check the current store rules
before phase 2.

**Recommendation**: phase 1 a transfer code, with or soon after the server
switch. Phase 2 Apple and Google sign-in, with "Delete my account", before a
public release.

## What moves

Everything is stored under the player id, so the new phone becomes that player
and nothing is copied: diamonds, the ledger and unclaimed prizes; gold and
owned and worn cosmetics (the server's save); premium items; best scores, rooms
and board runs; milestones, ladder steps, the streak; today's Daily Run tries;
name and flyer; synced settings. Stays on each phone: `Profile.LOCAL_KEYS`,
the push token (re-registered), Your runs (`user://runs.json`). Never merged:
the new phone's own progress is replaced, so nobody can farm several accounts
into one.

## Screens (mockups on the page)

1. Settings: a new Account group with "Move to a new phone".
2. Move to a new phone: "This is my old phone, Get a code" and "This is my new
   phone, Enter a code".
3. Old phone shows the code (`K7QF-3MZD-PX9W`, works once, 24 h, Copy, Cancel
   code), after queued runs and the save are sent; warns that anyone with the
   code gets the progress and that this phone starts over once it is used.
4. New phone enters the code: three groups of four, look-alikes (O/0, I/1)
   accepted, tries left shown on an error.
5. Confirm and overwrite: this phone vs moving here (best, coins, diamonds,
   items, name); "This phone's own progress is lost, and your old phone is
   signed out." Move progress here / Cancel.
6. Old phone afterwards: "Moved to another phone", Play as a new player.

## Server

- `POST /v1/transfer/create` (old phone): a 12-character Crockford base32 code
  (60 bits), 24 h, single use; cancels earlier codes; 5 a day per player.
- `POST /v1/transfer/cancel`.
- `POST /v1/transfer/preview {code}` (new phone): the summary for screen 5;
  counts as a try.
- `POST /v1/transfer/redeem {code, device_key}`: one transaction: code used,
  every session and device key of the player revoked, the new key enrolled,
  a session returned. The new phone's own anonymous player is left behind.
- Afterwards any call from the old phone: `401 {"error": "account_moved"}`; the
  client shows screen 6, then signs up as a new player.
- Tables: `transfer_codes` (sha-256 `code_hash`, never the code; `player_id`,
  `created_at`, `expires_at`, `used_at`, `used_by_ip`), revocable
  `device_keys` and sessions, `transfer_attempts` (7 days), `transfer_log`.

## Conflicts

One phone per account: a transfer moves it, never shares it. Two phones with
the same code: the first redeem wins, the second gets "already used". Play on
the old phone after the code was shown is lost once it is used (screen 3 says
so). The new phone's own progress is replaced after screen 5. Moving back works
the same way; Daily Run tries and prizes stay with the player.

## Abuse

- Guessing: 60 bits, 24 h, single use; 5 tries per device per hour, 20 per IP
  per hour, then a 1-hour block.
- Stolen codes: the warning on screen 3, never in links, push or logs, can be
  cancelled, screen 5 shows what moves.
- Farming and merging: no merge, diamonds can't move between players.
- Code spam: 5 a day, a new one cancels the old one.
- Resetting Daily Run tries: tries belong to the player.
- Selling accounts: possible; everything is cosmetic, not worth blocking.
- Replay: HTTPS, single use, one transaction.

## Open questions

1. Transfer code first, Apple and Google sign-in later: OK?
2. Code lifetime: 24 hours, or 1 hour?
3. Should Your runs move too (an upload), or stay on the old phone?
4. Phase 2 (sign-in plus Delete my account) before the public release?
