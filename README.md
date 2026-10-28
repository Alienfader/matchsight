# Matchsight

Your team's live match on **Meta Ray-Ban Display** glasses, with an AI match analyst you
can ask out loud.

Pick your Premier League and Champions League clubs once. When one of them plays,
Matchsight follows the match automatically and floats it in front of you in a frosted,
cyan-to-lavender glass style: the score capsule with the event timeline, goal / red-card /
VAR celebrations, a stacked starting-XI card carousel with live player stats, a line-art
formation board, and **AI Insight** pages from Meta's Muse Spark. Navigate with the
**Neural Band**; pinch and hold to ask a question by voice.

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

## Honest by design

- The AI analyst answers **only from numbered match facts** (score, events, lineups,
  formations, stats). Every answer is validated before it reaches the glasses; when the
  data can't answer, it says so. The footer names the source (`Muse Spark · observed`,
  `Data only`, `Mock AI`).
- Win probabilities are **API-Football's own pre-match prediction**, labelled as such.
- **Demo mode** replays a scripted Arsenal v Chelsea match (real squads, invented events),
  labelled `scripted` on the glasses.

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
| Swipe down | AI Insight page |
| Pinch and hold | Ask the analyst by voice |

Thumb + middle-finger pinch is the glasses' own back gesture and leaves the app.

## Data and trademarks

Match data, crests and player photos come from API-Football at run time and belong to their
respective owners; club names and crests are trademarks of their clubs. The recorded API
responses under `CopaHUDCore/Tests/CopaHUDCoreTests/Resources/` are test fixtures.
