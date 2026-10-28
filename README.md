# Matchsight

Your team's live match on **Meta Ray-Ban Display** glasses, with an AI match analyst you
can ask out loud.

Pick your Premier League and Champions League clubs once. When one of them plays,
Matchsight follows the match automatically and floats it in front of you in a frosted,
cyan-to-lavender glass style: the score capsule with the event timeline, goal / red-card /
VAR celebrations, a stacked starting-XI card carousel with live player stats, a line-art
formation board, and **AI Insight** pages from Meta's Muse Spark. Navigate with the
**Neural Band**; pinch and hold to ask a question by voice.

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
         Cloudflare Worker (holds the Meta key) ──▶ Muse Spark · Muse Voice Transcribe
```

- **iPhone app** (`CopaHUD/`, SwiftUI): polls API-Football, runs the follow policy, draws
  every glasses page with SwiftUI and sends it to the display as one picture.
- **CopaHUDCore** (`CopaHUDCore/`, Swift package): the pure, unit-tested logic — feed
  mapping, match engine, HUD state machine, follow policy, AI insight prompting and
  validation.
- **AI proxy** (`proxy/`, Cloudflare Worker): keeps the Meta Model API key off the phone and
  allows only the two models the app uses. See `proxy/README.md`.

(Internal names — the Xcode project, bundle ID and Swift package — are still `CopaHUD`:
the app started in June 2026 as a World Cup companion.)

## Meta AI tooling

- **Muse Spark (`muse-spark-1.3`) as a grounded analyst.** The phone turns the live match
  into numbered facts (`F1`, `F2`, …: score, events, lineups, formations, stats) and asks
  Muse Spark for one short insight under a strict JSON schema. Each answer must declare its
  basis (`observed`, `data_inference` or `general_tactics`) and cite the fact IDs it used.
- **A validator between the model and the glasses.** `InsightValidator` rejects answers that
  cite unknown facts, cite nothing when they should, run past the 150-character limit (it
  never truncates a claim), or describe things only video could show ("pressing",
  "positioning"…). A rejected or failed call falls back to a data-only template, so the
  insight page never goes blank.
- **Muse Voice Transcribe (`muse-voice-transcribe-1.0`) for spoken questions.** Pinch and
  hold on the Neural Band records up to 15 s of 16 kHz audio; the transcript (up to 200
  characters) goes to Muse Spark, and spoken answers must cite at least one fact.
- **Cost-aware scheduling.** Insights refresh automatically as the match changes, but
  unchanged data never re-asks the model (up to 10 minutes), a burst of events waits at
  least 30 s, and repeat questions on unchanged data are answered from a cache.
- **Meta Wearables Device Access Toolkit 1.0.1** for the display and the Neural Band, and a
  Cloudflare Worker that holds the Meta key and allows only the two models above.

## Honest by design

- The analyst answers **only from match facts**; when the data can't answer, it says so.
  The footer names the source (`Muse Spark · observed`, `Data only`, `Mock AI`).
- Win probabilities are **API-Football's own pre-match prediction**, labelled as such.
- **Demo mode** replays a scripted Arsenal v Chelsea match (real squads, invented events),
  labelled `scripted` on the glasses and flagged as scripted to the model.

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
- `CopaHUDCore` holds the logic as a plain Swift package with 304 unit tests, using recorded
  API-Football responses as fixtures.

## Demo

Turn on **Settings → Demo mode** to replay the scripted Arsenal v Chelsea match without an
API-Football key. With a key, the app follows your clubs' real matches.

## Requirements

- iPhone with iOS 17+, Meta Ray-Ban Display glasses, the Meta AI app with Developer Mode on.
- Xcode 26 with the Meta Wearables Device Access Toolkit 1.0.1 (Swift Package Manager).
- An [API-Football](https://www.api-football.com/) key (entered in the app; stored in the
  iOS Keychain).
- Optional, for the AI analyst: a Meta Model API key behind your own deployment of the
  Worker in `proxy/` (the app stores the Worker URL and app token in the Keychain).

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
| Pinch (thumb + index) or swipe right | Next page / next player |
| Swipe left | Previous |
| Swipe up | Home (score capsule) |
| Pinch and hold | Ask the analyst by voice |

Thumb + middle-finger pinch is the glasses' own back gesture and leaves the app.

## Data and trademarks

Match data, crests and player photos come from API-Football at run time and belong to their
respective owners; club names and crests are trademarks of their clubs. The recorded API
responses under `CopaHUDCore/Tests/CopaHUDCoreTests/Resources/` are test fixtures.

## Project history

Matchsight began in June 2026 as CopaHUD, a World Cup companion for the glasses, which is
why the Xcode project, bundle ID and Swift package keep that name.

<!-- FOUNDER: what was built during the hackathon window -->

<!-- FOUNDER: AI-tools disclosure wording -->

## License

<!-- FOUNDER: license -->

