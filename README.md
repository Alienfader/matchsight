# Matchsight

Your team's live match, floating in front of you on **Meta Ray-Ban Display** glasses.

Pick your Premier League, Champions League, DFB-Pokal and Brazilian (Série A, Série B,
Copa do Brasil) clubs once. When one of them plays,
Matchsight follows the match automatically and shows it in a frosted, cyan-to-lavender
glass style: the score capsule with the event timeline, goal / red-card / VAR
celebrations, a stacked starting-XI card carousel with live player stats, and a line-art
formation board. Navigate with the **Neural Band**. Pinch and hold to ask a question about
the match by voice; Meta's Muse Spark answers from the live match data only.

Submitted to the **Meta Global AI Developer Hackathon 2026**, Startup track.

**Demo video:** <!-- FOUNDER: video link -->

## Who it's for

Fans who want to follow their team's match while away from a screen. Matchsight puts the
score, events and lineups in view, and answers spoken questions about the match, without
the fan taking out a phone. It picks the match itself, so there is nothing to set up on
match day.

## How it works

```
API-Football ──▶ iPhone app ──(Meta Wearables Device Access Toolkit)──▶ glasses display
                    │  ▲                                                   Neural Band input
                    ▼  │
         Cloudflare Worker (holds the keys) ──▶ Muse Spark · Muse Voice Transcribe · ElevenLabs TTS
```

- **iPhone app** (`CopaHUD/`, SwiftUI): polls API-Football, runs the follow policy, draws
  every glasses page with SwiftUI and sends it to the display as one picture.
- **CopaHUDCore** (`CopaHUDCore/`, Swift package): the pure, unit-tested logic — feed
  mapping, match engine, HUD state machine, follow policy, AI insight prompting and
  validation.
- **AI proxy** (`proxy/`, Cloudflare Worker): keeps the Meta Model API and ElevenLabs keys
  off the phone, allows only the models the app uses, and fixes the ElevenLabs voice and model
  on the server. See `proxy/README.md`.

(Internal names — the Xcode project, bundle ID and Swift package — are `CopaHUD`: the idea
came during the World Cup.)

## Meta AI tooling

- **Muse Spark (`muse-spark-1.3`) as a grounded match assistant.** The phone turns the live match
  into numbered facts (`F1`, `F2`, …: score, events, lineups, formations, stats) and asks
  Muse Spark for one short insight under a strict JSON schema. Each answer must declare its
  basis (`observed`, `data_inference`, `general_tactics` or `general_knowledge`) and cite the
  fact IDs it used.
- **A validator between the model and the glasses.** `InsightValidator` rejects answers that
  cite unknown facts, cite nothing when they should, run past the 150-character limit (it
  never truncates a claim), or describe things only video could show ("pressing",
  "positioning"…). A rejected or failed call falls back to a data-only template, so the
  insight page never goes blank.
- **Muse Voice Transcribe (`muse-voice-transcribe-1.0`) for spoken questions.** Pinch and
  hold on the Neural Band records up to 15 s of 16 kHz audio; the transcript (up to 200
  characters) goes to Muse Spark. Spoken answers about the match must cite at least one fact;
  a general question no fact covers ("Where is Chelsea from?") may be answered from Muse
  Spark's general knowledge, uncited and labelled `general knowledge` on the glasses. The
  glasses show each step: listening, transcribing, the question as heard with "Thinking…",
  then the answer under the question.
- **Look at a player (glasses camera, experimental, off by default).** Hold to ask and say "who's this?": the
  glasses take one photo, Apple's on-device text recognition reads the shirt number in the
  middle of the picture, and the player's detail card opens. It only ever names a starter
  in the lineups; same number on both teams, or none read, says so. Works on TV close-ups;
  players far away are too small to read. The photo stays on the phone and is not kept.
  In live testing it was slow (5–15 s per photo) and rarely found a readable number, so
  it is parked behind a Settings switch and not part of the demo.
- **Cost-aware scheduling.** Insights refresh automatically as the match changes, but
  unchanged data never re-asks the model (up to 10 minutes), a burst of events waits at
  least 30 s, and repeat questions on unchanged data are answered from a cache.
- **Meta Wearables Device Access Toolkit 1.0.1** for the display and the Neural Band, and a
  Cloudflare Worker that holds the Meta key and allows only the two models above.

## Honest by design

- Anything about the match comes **only from match facts**; when the data can't answer, the
  assistant says so. Spoken general questions (a club's city, a stadium) are answered from
  Muse Spark's general knowledge, never for the automatic insights, and labelled as such.
  The footer names the source (`Muse Spark · observed`, `Muse Spark · general knowledge`,
  `Data only`, `Mock AI`).
- Win probabilities are **API-Football's own pre-match prediction**, labelled as such.
- **Demo mode** replays a scripted Arsenal v Chelsea match (real squads, invented events),
  labelled `scripted` on the glasses and flagged as scripted to the model.
- The player card's heat map is **simulated, in demo mode only**, and labelled `SIMULATED`
  on the glasses: API-Football has no positional data, so a real match shows only the
  player's formation spot. The model never sees the heat map.
- In demo mode the player detail card's figures are **scripted** and marked `scripted`:
  goals, assists, cards and minutes follow the script's events; the other counts are
  invented, scaled by minutes played and position. The model never sees them.

## Engineering notes

Learned on real glasses:

- The toolkit's display DSL couldn't carry this design, so every page is drawn on the phone
  with SwiftUI `ImageRenderer` and sent as one image. At 360 px a send takes about 0.33 s
  (about 0.9 s at 600 px).
- Overlapping sends caused "Timed out waiting for display response" errors (9 in testing).
  Serialising sends, latest frame wins, brought that to 0 in testing.
- The display is additive: black is transparent and dark colours look faint, so the style
  uses bright fills on black.
- AI calls never block rendering or gestures; they run behind the current page and fail
  back to data.
- `CopaHUDCore` holds the logic as a plain Swift package with 432 unit tests, using recorded
  API-Football responses as fixtures.

## Demo

Turn on **Settings → Demo mode** to replay the scripted Arsenal v Chelsea match without an
API-Football key. With a key, the app follows your clubs' real matches.

The scripted match plays 90 minutes in about 90 seconds (the TV delay doesn't apply to it).
A walkthrough:

1. Settings: **Demo mode** on, **HUD style → Dark glass**, **Sound** on.
2. Connect the glasses. The first time, the **gesture guide** asks for each gesture once.
3. Watch it play: Saka scores at 18' (banner and chime), Chelsea equalise at 28', a yellow
   card at 36' (a one-line notice), João Pedro's 42' goal is ruled out by VAR at 44', the
   half-time whistle, substitutions, and Eze's 89' winner. At full time Muse Spark's recap is
   read aloud.
4. Meanwhile swipe through the pages, pinch a player on the board for their card (demo
   figures are marked scripted), and pinch and hold to ask "who scored first?". The answer
   is read aloud through the glasses.

Watching on TV? **Settings → TV delay** (up to 5 minutes) holds the score, events and goal banners on
the glasses so they never arrive before the broadcast shows the goal. **Sync with TV** sets
it for you: pick the next whole minute the TV clock will show and tap when it gets there.
The feed gives whole minutes, so the live clock is pinned to the moment the minute ticks over
(within about 4 s at an 8 s poll); not available at half-time or in stoppage time. A TV within
30 s of the live clock gets no delay: goals reach the feed after a live broadcast shows them, so
any delay would only make the alert later. The phone's Today list is not delayed.

**Settings → HUD style → Dark glass** draws every page in one near-black card in the same
place, with the score and minute always on top, fewer words and bigger figures: the latest
goals and cards by the names players are known by, the XI board as the player browser, and
four key figures per player picked for the position, without the zeros. It adds less light
over the TV. Classic stays the default.

**Settings → Battery saver** saves the glasses' battery during a long match. After 20 seconds
with no gestures and nothing new, **Dim** (the default) shows only a faint score line on black;
**Display off** turns the glasses display off. Goals, cards, VAR, voice and any gesture bring
the full page back, and the first gesture only wakes it. The Meta SDK has no brightness control
or battery reading, so this is the lever the app has. If the glasses report a critical battery,
overheating or a power shutdown, or end the session and don't come back within 15 seconds, the
phone says so.

## Requirements

- iPhone with iOS 17+, Meta Ray-Ban Display glasses, the Meta AI app with Developer Mode on.
- Xcode 26 with the Meta Wearables Device Access Toolkit 1.0.1 (Swift Package Manager).
- An [API-Football](https://www.api-football.com/) key (entered in the app; stored in the
  iOS Keychain).
- Optional, for voice Q&A and AI Insight: a Meta Model API key behind your own deployment of the
  Worker in `proxy/` (the app stores the Worker URL and app token in the Keychain).
- Optional, for natural spoken answers: an ElevenLabs key and voice ID set as Worker secrets
  (`ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`). Library voices need a paid ElevenLabs plan;
  the built-in voices work on the free plan.

## Build and test

```
cd CopaHUDCore && swift test      # core logic
cd proxy && node --test           # AI proxy
```

Open `CopaHUD.xcodeproj`, set your own signing team, and run on a device. The default
build uses Meta's **Developer Mode** (`MetaAppID` 0). To build against a Wearables Developer
Center project (for "Hey Meta, start Matchsight"), see `scripts/build-registered.sh`; its
Application ID and Client Token are read from the macOS Keychain, never from the repo.

## Neural Band

| Gesture | Action |
|---|---|
| Swipe right / left | Next / previous page; inside the starting XI, next / previous player |
| Pinch on the formation | Step into the players (swiping past either end comes back out) |
| Pinch on a player card | Open / close that player's match stats |
| Swipe up | Home (score capsule) |
| Swipe down | AI Insight page |
| Pinch and hold | Ask a question by voice |

Thumb + middle-finger pinch is the glasses' own back gesture and leaves the app.

Dots along the bottom of each page show where you are in the deck, and the current dot
lights up cyan for a moment whenever a gesture reaches the app. If a swipe doesn't light it,
the band didn't send it: swipe again, or pinch, which moves through every page.

## Data and trademarks

Match data, crests and player photos come from API-Football at run time and belong to their
respective owners; club names and crests are trademarks of their clubs. The recorded API
responses under `CopaHUDCore/Tests/CopaHUDCoreTests/Resources/` are test fixtures.

## Project history

The idea for Matchsight came during the World Cup, which is why the Xcode project, bundle
ID and Swift package are named CopaHUD.

The Muse Spark and Muse Voice Transcribe integration was added during the hackathon, once
Meta issued the API credits.

<!-- FOUNDER: what was built during the hackathon window -->

<!-- FOUNDER: AI-tools disclosure wording -->

**ElevenLabs (non-Meta).** Spoken answers can be read aloud with ElevenLabs text to speech
(`eleven_flash_v2_5`). It's called through the same Cloudflare Worker, which holds the
ElevenLabs key, so the key never ships in the app. ElevenLabs only receives the text of Muse
Spark's answer, to turn it into audio. It never sees the match data or your recorded question.
It's optional (Settings → Voice), and the app falls back to the iPhone's built-in voices if
it's off or unreachable.

## License

MIT. See [LICENSE](LICENSE). Match data, crests and player photos are not covered; see
[Data and trademarks](#data-and-trademarks).

