# Store listing, English (en-US)

Paste into Play Console → Grow users → Store presence → Main store listing.
Limits: app name 30, short description 80, full description 4000, release notes 500 characters.
Counts below are measured on the text between the fences.

## App name (7 / 30)

```
Flapjaw
```

Longer option if the plain name is taken in search (25 / 30): `Flapjaw: Tap, Flap, Dodge`

## Short description (77 / 80)

```
Tap to flap, bounce wall to wall, dodge spikes. Daily Run, Battles and Duels.
```

## Full description (1868 / 4000)

```
Tap to flap. Bounce from wall to wall. Don't touch the spikes.

Flapjaw is a quick arcade game you play with one thumb. Every tap gives a flap, every wall sends you back the other way, and every room tries something new to stop you.

ROOMS THAT KEEP CHANGING
Each run takes you through room after room: saws, lava, lasers, pendulums, crushers, wind, caves, moving blocks and boss rooms. The further you get, the trickier they get. No two runs are the same.

DAILY RUN
One map a day, the same for every player in the world. You get three tries; your best one counts on the Daily Run board. Top 10 win diamonds when the day is over.

BATTLE
Challenge a friend or a random player to a Battle. Each round is a fresh map: one of you plays it first, the other plays the same map with that run flying next to them as a see-through rival. The higher score wins the round, and the first to six rounds wins the Battle. Play your turn whenever you like; the game tells you when it's your move.

DUEL
Play live. You and your rival fly the same map at the same time and see each other's bird as it happens. Best of three. Invite a friend with a code, or find a rival in seconds.

FAIR SCORES
Every run on the boards is checked by replaying it on our server, so the top scores are real. Watch the replays of the best runs and see how they did it.

LOOK THE WAY YOU WANT
Unlock flyers, worlds, trails, portals, music, crash effects and leaderboard plates with coins you earn by playing. Everything you can buy only changes how the game looks. Every flyer has the same size and the same moves: no pay-to-win, ever.

FREE TO PLAY
Flapjaw is free. You get three free revives a day; after that you can watch an optional ad for one more chance. Ads only show when you ask for one.

Bot players in Battles and Duels are always marked BOT.

Questions or ideas? Mail us at {{CONTACT_EMAIL}}.
```

## Release notes, 0.1.4 (360 / 500)

```
What's in Flapjaw 0.1.4:
• Duel: play a friend or a random rival live on the same map, best of three.
• Battle: take turns against a friend, first to six rounds wins.
• Daily Run: one map a day for everyone, three tries, top 10 win diamonds.
• Battle and Duel always play the newest version, so both players get the same map.
• Lots of fixes and smoother play.
```

## Notes before pasting

- Replace `{{CONTACT_EMAIL}}` (open question, see `README.md`).
- "Top 10 win diamonds" and "three free revives a day": both match the current rules
  (`meta/daily_run_rules.gd`, `docs/REVIVE.md`). Change the text if those numbers change.
- Diamond packs and the Revive Pass are not open yet (`services/store_service.gd`: the store
  is closed until Google Play Billing is in). The text says nothing about buying diamonds, so it
  stays true either way. Once they open, the listing gets "Contains in-app purchases"
  automatically from the Console's declarations.
- Don't add "best", "#1", emoji in the title or calls to action like "Download now": Play's
  metadata policy rejects them.
