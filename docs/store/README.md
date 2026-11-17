# Store listing kit

Everything Google Play (and later the App Store) asks for, ready to paste once the organisation
account is verified. App id `com.mxndarijn.spikey`, name Flapjaw, version 0.1.4.

| File | What |
| --- | --- |
| `listing_en.md` | English name, short and full description, 0.1.4 release notes, with character counts |
| `listing_nl.md` | The same in Dutch |
| `privacy.html` | The privacy policy, a self-contained page to host |
| `data_safety.md` | Play Console App content: ads, app access, target audience, data safety form, IARC content rating, ads details |
| `graphics.md` | Icon, feature graphic and screenshot specs, a suggested set, how to make them |

## Placeholders to fill in

Search for `{{` in `listing_*.md` and `privacy.html`.

| Placeholder | Where | What |
| --- | --- | --- |
| `{{CONTACT_EMAIL}}` | listings, privacy | Public support and privacy address. Play shows it on the listing as the developer email, so use a role address on the company domain (for example `support@<domain>`), not a personal one. |
| `{{COMPANY_NAME}}`, `{{COMPANY_ADDRESS}}`, `{{KVK_NUMBER}}` | privacy | The legal name, address and Chamber of Commerce number, as on the D-U-N-S record. Play shows the organisation's name and address on the listing anyway. |
| `{{EFFECTIVE_DATE}}` | privacy | The day the page goes live. |
| `{{PROXY_LOG_SENTENCE}}` | privacy | Whether Traefik on the VM keeps access logs with IP addresses. If it doesn't: delete the placeholder. If it does: "Our web proxy keeps standard request logs (IP address, time, address requested) for N days for security." The backend itself stores IPs only for transfers (`backend/src/transfer.rs`); rate limits are in memory (`backend/src/limits.rs`). |
| `{{INACTIVE_RETENTION_SENTENCE}}` | privacy | Nothing deletes inactive accounts today. Either delete this line, or decide a rule (for example "Accounts not used for 24 months are deleted") and build the clean-up job first. |

## Hosting the privacy policy

Play needs a public, non-PDF, non-editable URL that works without signing in. Options:

1. **On the game server at `https://flapjaw.mn-platform.tech/privacy`** (recommended): one
   axum route in `backend/src/app.rs` that returns the page with `include_str!`, so it ships
   and versions with the server. Small backend change, its own branch and deploy. Deletion
   link: `/privacy#delete`.
2. A static page on the company website, for example `https://<domain>/flapjaw/privacy`. Needed
   anyway for `app-ads.txt` (`data_safety.md`, "Ads declarations"): the Play listing's
   developer website must serve `/app-ads.txt` at its root, and `mn-platform.tech` is the
   platform's domain, not the company's.
3. GitHub Pages from this repo (only if the repo or a docs repo is public).

Whatever is picked, put the same URL in Play Console (App content → Privacy policy, and Store
settings → Store listing contact details) and, later, in App Store Connect.

## Open questions for the user

1. **Contact email** for the listing and the privacy page.
2. **Company details** for the privacy page: legal name, address, KvK number.
3. **Where the privacy page lives**: the server route `/privacy` (needs a small backend change
   and deploy), or the company website.
4. **Developer website** for the Play listing, and whether it can serve `app-ads.txt`.
5. **Traefik access logs**: kept or not, and how long (for the privacy page).
6. **Inactive accounts**: keep forever until asked, or delete after a period?
7. **Target age**: 13+ is what these answers assume. Under 13 would change ads and the data
   safety answers (`data_safety.md`).
8. **Content rating answer for crashes**: "no violence" (likely PEGI 3) or "mild cartoon
   violence" (PEGI 7). Either is honest; PEGI 3 widens reach.
9. **Release notes wording**: written as an update ("What's in 0.1.4"). If 0.1.4 is the first
   public release on Play, a "Welcome to Flapjaw" version may read better.

## Follow-ups found (not done here, docs only)

- **In-app account deletion**: Play wants deletion reachable in the app and on the web. Today
  it's by email only. A "Delete my account" row in Settings → Account plus a server operation
  that removes `auth.users` (everything cascades: players, runs, profiles, wallets, push
  devices, battles; check `transfer_log`, which has no foreign key) would close it.
- **Privacy policy link in the game**: a "Privacy policy" row on Settings → About, next to Ad
  choices, opening the hosted URL.
- **`/privacy` route on the server** (if option 1 above).
- **Launcher icons**: the Android adaptive icon layers and the iOS 1024 icon are empty in
  `export_presets.cfg` (`graphics.md`, "Found while checking").
- **More `-Screen` options** in `tools/capture_screen.gd` (battle, duel, shop) for screenshots.
- **When Google Play Billing opens**: update the data safety form (Purchase history), the IARC
  questionnaire (in-game purchases) and the listing.
