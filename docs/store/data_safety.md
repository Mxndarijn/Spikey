# Play Console: App content answers

Play Console → Policy and programs → App content. Every answer below matches
`docs/store/privacy.html` and the code as of v0.1.4 (backend migrations in
`backend/migrations/`, `services/admob_ads.gd`, `services/push_service.gd`,
`export_presets.cfg`). Change both files together when the game's data use changes.

## Privacy policy

URL: the hosted copy of `privacy.html` (see `README.md`, "Hosting the privacy policy"),
for example `https://flapjaw.mn-platform.tech/privacy`.

## Ads

**Does your app contain ads? Yes.** Rewarded ads from Google AdMob, only when the player taps
"watch an ad" to revive. No banners, no interstitials. Play shows "Contains ads" on the listing.

## App access

**All functionality is available without special access.** There is no login: the phone makes
its own account at the first start. (If a reviewer can't reach Battle or Duel because no rival
is online: bots fill in, marked BOT, so nothing needs a test account.)

## Target audience and content

- **Target age groups: 13–15, 16–17, 18 and over.** Don't tick any group under 13.
  - Under 13 puts the app in the Families policy: ads would have to be child-directed
    (`tag_for_child_directed_treatment`, no personalised ads), the Ad choices / consent flow and
    the data safety answers change, and a teacher-approved review may follow. The game doesn't do
    that today (`services/admob_ads.gd` sets only `max_ad_content_rating = PG`).
- **Could the app unintentionally appeal to children? Answer honestly: the cartoon look may.**
  If Google asks, explain: a fast reflex arcade game with online leaderboards and live play
  against strangers, designed for teens and adults, ads capped at PG. If Google decides it does
  appeal to children, it will ask for a neutral age screen; that's a game change (follow-up).
- **Store listing doesn't target children**: the descriptions in `listing_*.md` don't mention
  kids or families. Keep it that way.

## Data safety form

### Overview questions

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS and WSS to flapjaw.mn-platform.tech; Google's SDKs use TLS) |
| Does your app allow users to create an account? | **Yes → Other**: an account is made automatically for each device at the first start (no username, password or OAuth). Describe it as "Automatic device account with a user-chosen nickname". |
| Do you provide a way for users to request that their data is deleted? | **Yes** |
| Delete account URL (asked because accounts exist) | The privacy page's deletion section, for example `https://flapjaw.mn-platform.tech/privacy#delete` |

Note on accounts: Play's account deletion rule applies to apps where an account is created.
The device-key account is one (it has a player name, runs and a save on our server), so declare
it, give the deletion URL, and plan the in-app "Delete my account" button (`README.md`,
follow-ups). Until that exists, deletion is by email as the privacy page says.

### Data types

"Collected" = sent off the phone. "Shared" = passed to another company for its own use (service
providers acting for us, like Firebase delivering pushes, don't count as sharing; AdMob does
count, it uses the data for its own ad purposes). "Optional" = the user can use the app without
it.

| Category → type | Collected | Shared | Optional? | Purposes | Who |
| --- | --- | --- | --- | --- | --- |
| Personal info → **Name** | No | No | | | We don't collect real names. The player name is a user-chosen nickname: declare it under "Other info" below, not here. |
| Personal info → **User IDs** | **Yes** | No | Required | App functionality, Fraud prevention / security, Account management | Our server: the random player id and the hashed device key |
| Personal info → **Other info** | **Yes** | No | Required | App functionality | Our server: the player name (nickname), shown publicly on boards |
| Location → **Approximate location** | **Yes** | **Yes** | Optional (only with ads) | Advertising or marketing, Fraud prevention | AdMob derives it from the IP address. Our server stores the time zone offset only, which is not location. |
| Location → Precise location | No | No | | | |
| App activity → **App interactions** | **Yes** | **Yes** | Required (ours); optional (AdMob) | App functionality, Fraud prevention (ours); Advertising, Analytics (AdMob) | Our server: runs, taps (replays), Battles, Duels. AdMob: ad interactions. |
| App activity → **Other user-generated content** | No | No | | | Replays are tap timings, covered by App interactions; no free text other than the name |
| App activity → In-app search history, Installed apps, Web browsing | No | No | | | |
| App info and performance → **Diagnostics** | **Yes** | **Yes** | Optional (only with ads) | Advertising, Analytics, Fraud prevention | AdMob SDK only. We have no crash reporting (Crashlytics off). |
| App info and performance → Crash logs | No | No | | | (AdMob says "may" for crash logs; Google's own AdMob data-disclosure page lists Diagnostics and Crash logs. Tick Crash logs too if the current AdMob disclosure lists it when you fill this in.) |
| Device or other IDs → **Device or other IDs** | **Yes** | **Yes** | Required (push token while alerts are on); optional (ad id) | App functionality (push token); Advertising, Analytics, Fraud prevention (advertising id, AdMob) | Our server: FCM/APNs push token. AdMob: advertising id / app set id. |
| Financial info → Purchase history | No (today) | No | | | Store is closed in 0.1.4. When Google Play Billing opens: **Yes, collected, not shared, App functionality** (which pack was bought, kept in the save). Update this form then. |
| Financial info → Payment info, Credit score | No | No | | | Google Play handles payment. |
| Health, Messages, Photos, Audio, Files, Calendar, Contacts, Email, Phone number | No | No | | | |

Each "Yes" row also asks **"Is this data processed ephemerally?"**: **No** for everything on our
server (it's stored). AdMob: No.

## Content rating (IARC questionnaire)

Play Console → App content → Content rating → Start questionnaire. Category: **Game**.
Email: the contact email. Expected result: PEGI 3 or PEGI 7, ESRB Everyone, USK 0/6, plus the
interactive elements "Users Interact" and "In-Game Purchases" (the latter once the store opens;
answer for the build you submit).

| Question group | Answer | Why |
| --- | --- | --- |
| Violence | **No** to realistic violence, blood, gore. Cartoon/fantasy violence: **No** (a bird bumping into spikes and bursting into feathers is not violence against characters). If you prefer to be careful, answer "mild cartoon violence: yes, against non-human characters, not realistic": that gives PEGI 7. | Crash effects are a feather puff or similar |
| Fear | **No** | Haunted world theme is cosmetic and cute; no horror |
| Sexuality, nudity | **No** | |
| Language | **No** | Names pass a word filter (`20261108210000_name_filter.sql`) |
| Controlled substances (drugs, alcohol, tobacco) | **No** | |
| Crude humour | **No** | |
| Gambling: real or simulated gambling | **No** | No loot boxes, no random paid rewards. Diamond packs give a fixed amount. |
| Does the app let users interact or exchange content? | **Yes** | Public player names, leaderboards, replays, live Duels with strangers. No chat. |
| Does the app share the user's location with other users? | **No** | |
| Does the app allow users to purchase digital goods? | **No** for 0.1.4 (store closed); **Yes** once Billing opens: redo the questionnaire then | |
| Does the app contain ads? / Unrestricted internet | Ads: yes (in the Ads section above). Unrestricted internet browsing: **No** | |

## Ads declarations, detail

- **Ad formats**: rewarded video only (`services/admob_ads.gd`), shown only after the player
  taps to watch one.
- **Ad content rating**: max PG (`MAX_AD_CONTENT_RATING_PG`). In AdMob → Blocking controls you
  can additionally block sensitive categories (gambling, dating, alcohol) for a teen audience;
  recommended.
- **Consent (EEA, UK, Switzerland)**: Google's UMP consent form runs before the ads SDK starts;
  without consent no ad loads. The AdMob console still needs the European consent message
  created under Privacy & messaging (`docs/REVIVE.md`, "AdMob"), else the form never shows.
- **Ad choices later**: Settings → About → Ad choices (only shown where required).
- **iOS (App Store later)**: `NSUserTrackingUsageDescription` is in the iOS preset; create the
  IDFA explainer message in AdMob too. App Store privacy labels: same data as the table above,
  with "Used to track you: Device ID, Advertising Data" only when ATT is allowed.
- **Families ads program**: not joined (target 13+).
- **app-ads.txt**: Play and AdMob want `https://<developer website>/app-ads.txt` with the line
  AdMob shows (`google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0`). The developer
  website in the Play listing must be the domain that serves it. See `README.md`.

## Other App content items

| Item | Answer |
| --- | --- |
| News app | No |
| COVID-19 contact tracing | No |
| Government app | No |
| Financial features | None |
| Health | None |
| Advertising ID (Android 13+, AD_ID permission) | **Yes, the app uses an advertising ID**, for Advertising and Analytics (AdMob). The AdMob SDK adds the permission to the manifest. |
| Photo and video permissions, Foreground service, Exact alarms | Not used |
| Notifications (Android 13+ POST_NOTIFICATIONS) | Used for Board alerts and Battle turns. Not a Console declaration, but check the built manifest has it so Android asks the player. |
